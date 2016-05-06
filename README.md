
## Containers Tutorial
Walks through container networking and concepts step by step

### Prerequisites 
1. [Download Vagrant](https://www.vagrantup.com/downloads.html)
2. [Download Virtualbox](https://www.virtualbox.org/wiki/Downloads)

### Setup
1. Get the Vagrantfile
```
$ curl https://raw.githubusercontent.com/jainvipin/tutorial/master/Vagrantfile -o Vagrantfile
```

2. On `Microsoft Windows systems` create resolv.conf file in the current directory,
that would be needed by the VMs to access outside network. Ths next step will fail
if this is not specified correctly. On `Mac` the Vagrant bringup automatically
copies this file from `/etc/resolv.conf`

```
$ cat resolv.conf
domain foobar.com
nameserver 171.70.168.183
nameserver 173.36.131.10
```

3. Start a small two-node cluster
```
$ vagrant up
```

4. Log into one of the VMs, confirm all looks good
```
$ vagrant ssh tutorial-node1
vagrant@tutorial-node1:~$ docker ps
vagrant@tutorial-node1:~$ etcdctl cluster-health
vagrant@tutorial-node1:~$ ifconfig docker0
vagrant@tutorial-node1:~$ ifconfig eth1
vagrant@tutorial-node1:~$ ifconfig eth0
vagrant@tutorial-node1:~$ netctl version
```
In the above output, you'll see:
- `docker0` interface corresponds to the linux bridge and its associated
subnet `172.17.0.1/16`. This is created by docker daemon automatically, and
is the default network containers would belong to when an override network
is not specified
- `eth1` in this VM is the interface that connects to external network (if needed)
- `eth0` is the management interface, on which we ssh into the VM


### Chapter 1 - Dcoker's libnetwork - Container Network Model 

CNM (Container Network Model) is Docker's libnetwork network model for containers
- An endpoint is container's interface into a network
- A network is collection of arbitrary endpoints
- A container can belong to multiple endpoints (and therefore multiple networks)

#### Default networking

Let's examine the networking a container gets upon vanilla run
```
vagrant@tutorial-node1:~$ docker network ls

vagrant@tutorial-node1:~$ docker run -itd --name=vanilla-c alpine /bin/sh
 
vagrant@tutorial-node1:~$ ifconfig 
```

You will see that it has a `virtual ethernet interface` that could look like `vethedba290`. More importantly it is allocated an IP address from default docker 
bridge `docker0`, likely `172.17.0.3`, and can be examined using
```
vagrant@tutorial-node1:~$ docker network inspect bridge
vagrant@tutorial-node1:~$ docker inspect --format '{{.NetworkSettings.IPAddress}}' vanilla-c
```

The other pair of veth interface is put into the container with the name `eth0`
```
vagrant@tutorial-node1:~$ docker exec -it vanilla-c /bin/sh
/ # ifconfig eth0
```

All traffic to/from this container is Port-NATed to the host's IP (on eth0).
The Port NATing on the host is done using iptables, which can be seen as a
MASQUERADE rule for outbound traffic on all ports
```
$ vagrant@tutorial-node1:~$ sudo iptables -t nat -L -n
```

#### Multi-host networking, using overlay driver

Docker engine has a built in overlay driver that can be use to connect
containers across multiple nodes. 
```
vagrant@tutorial-node1:~$ docker network create -d=overlay --subnet=10.1.1.0/24 overlay-net
vagrant@tutorial-node1:~$ docker network inspect overlay-net
vagrant@tutorial-node1:~$ docker run -itd --name=overlay-c1 --net=overlay-net alpine /bin/sh
vagrant@tutorial-node1:~$ docker inspect --format '{{.NetworkSettings.IPAddress}}' overlay-c1
```

Let's ssh into the second node using `vagrant ssh tutorial-node2`, and spin up a 
new container on it
```
vagrant@tutorial-node2:~$ docker run -itd --name=overlay-c2 --net=overlay-net alpine /bin/sh

vagrant@tutorial-node2:~$ docker exec -it overlay-c2 /bin/sh

/ # ping overlay-c1
```
The above will resolve the IP address of `overlay-c1` and be able to reach another container
across a different host.

#### Multi-host networking, Using remote drivers

Let's use the same example as above to spin up two containers on the two nodes

```
vagrant@tutorial-node1:~$ docker network create -d=netplugin --subnet=10.1.2.0/24 contiv-net

vagrant@tutorial-node1:~$ docker run -itd --name=contiv-c1 --net=contiv-net alpine /bin/sh

vagrant@tutorial-node2:~$ docker run -itd --name=contiv-c2 --net=contiv-net alpine /bin/sh

vagrant@tutorial-node2:~$ docker exec -it contiv-c2 /bin/sh

/ # ping contiv-c1

/ # exit

```

#### Connecting containers to external networks

There are two ways to connect to the external networks:

#### Host NATing: Using default bridge network 

Docker overlay driver uses the linux bridge (docker_gwbridge) based PNAT to reach out and port mappings
for others to reach to the container

```
vagrant@tutorial-node1:~$ docker exec -it overlay-c1 /bin/sh
vagrant@tutorial-node1:~$ ifconfig -a
```

What you see is that container has two interfaces belonging to it:
- eth0 is reachability into the `overlay-net` 
- eth1 is reachability for container to the external world and outside
traffic to be able to reach the container `overlay-c1`. This also relies on the host's dns
resolv.conf as a default way to resolve non container IP resolution.

```
vagrant@tutorial-node2:~$ docker exec -it contiv-c2 /bin/sh

/ # ping contiv.com

/ # exit
```

Similarly outside traffic can be exposed on specific ports using `-p` command
```
vagrant@tutorial-node1:~$ nc -zvw localhost 9099
nc: connect to localhost port 9099 (tcp) failed: Connection refused

vagrant@tutorial-node1:~$ docker run -itd -p 9099:9099 --name=contiv-exposed --net=contiv-net alpine /bin/sh

vagrant@tutorial-node1:~$ nc -zvw localhost 9099
Connection to localhost 9099 port [tcp/*] succeeded!
```

#### Natively connecting to the external networks

Remote drivers, like Contiv, can provide an easy way to connect to external
layer2 or layer3 networks using BGP or standard L2 access into the network.

This is done using vlan network for example

```
vagrant@tutorial-node1:~$ docker network create -e=vlan -d=netplugin --subnet=10.1.2.0/24 contiv-vlan-net

vagrant@tutorial-node1:~$ docker run -itd --name=contiv-c3 --net=contiv-vlan-net alpine /bin/sh

vagrant@tutorial-node2:~$ docker run -itd --name=contiv-c4 --net=contiv-vlan-net alpine /bin/sh

vagrant@tutorial-node2:~$ docker exec -it contiv-c4 /bin/sh

/ # ping contiv-c3

```

Now on the node tutorial-node2, run tcpdump on eth2 to ensure that packets are seen without any overlay or encap

```
vagrant@tutorial-node1:~$ sudo tcpdump -i eth2

```
[https://github.com/contiv/demo/blob/master/net/Bgp.md] describes how can you use BGP with Contiv to provide
native container connectivity and reachability to rest of the network
```

#### Applying policies between containers

Remote drivers, like Contiv, also provide a way to apply security policies between containers groups.
For this we create a simple policy called db-policy

```
vagrant@tutorial-node2:~$ netctl policy create db-policy
vagrant@tutorial-node2:~$ netctl policy rule-add db-policy 1 -direction=in -protocol=tcp -action=deny
vagrant@tutorial-node2:~$ netctl policy rule-add db-policy 2 -direction=in -protocol=tcp -port=8888 -action=allow -priority=10
```

Next we associate the policy with a group construct

```
vagrant@tutorial-node2:~$ netctl group create contiv-net db -policy=db-policy

vagrant@tutorial-node2:~$ docker run -itd --name=contiv-c4 --net=db-policy.contiv-net alpine /bin/sh
```

If we run containers against the group, we can verify the policy from any entity
```

### Chapter 2 - Kubernetes/CoreOS Container Neworking Interface


