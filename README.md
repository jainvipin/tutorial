
## Containers Tutorial
Walks through container networking and concepts step by step

### Prerequisites 
1. [Download Vagrant](https://www.vagrantup.com/downloads.html)
2. [Download Virtualbox](https://www.virtualbox.org/wiki/Downloads)

### Setup

#### Step 1: Get the Vagrantfile
Copy the [contents](https://raw.githubusercontent.com/jainvipin/tutorial/master/Vagrantfile) into a file called Vagrantfile. It could be done using curl as follows
```
$ curl https://raw.githubusercontent.com/jainvipin/tutorial/master/Vagrantfile -o Vagrantfile
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  6731  100  6731    0     0   8424      0 --:--:-- --:--:-- --:--:--  8424
```

Note: On Windows the file may be downloaded with `.txt` extension. Rename the file
if needed to remove the extension. Some steps are
documented [here](http://www.mediacollege.com/microsoft/windows/extension-change.html).

#### Step 2: Create resolv.conf file in the current directory, where you have copied the Vagrantfile.
This is used by the VMs to access outside network for downloading docker images in
rest of tuorial. The next steps will fail if this is not specified correctly.
On `Mac` or `Linux` based systems you may copy `/etc/resolv.conf` to current directory.
```
$ cp /etc/resolv.conf .

$ cat resolv.conf
domain foobar.com
nameserver 171.70.168.183
nameserver 173.36.131.10

$ ls
Vagrantfile	resolv.conf
```

#### Step 3: Start a small two-node cluster
```
$ vagrant up
Bringing machine 'tutorial-node1' up with 'virtualbox' provider...
Bringing machine 'tutorial-node2' up with 'virtualbox' provider...
 < more output here when trying to bring up the two VMs>
==> tutorial-node2: ++ nohup /opt/bin/start-swarm.sh 192.168.2.11 slave
$
```

#### Step 4: Log into one of the VMs, confirm all looks good

**Note**:
- On Windows, you will need a ssh client to be installed like putty, cygwin etc.
- The username/password for the VMs is vagrant/vagrant

```
$ vagrant ssh tutorial-node1
vagrant@tutorial-node1:~$ docker info
```
The above command shows the node information, version, etc.

```
vagrant@tutorial-node1:~$ etcdctl cluster-health
```
`etcdctl` is a control utility to manipulate etcd, state store used by kubernetes/docker/contiv

```
vagrant@tutorial-node1:~$ ifconfig docker0
docker0   Link encap:Ethernet  HWaddr 02:42:fb:53:27:56  
          inet addr:172.17.0.1  Bcast:0.0.0.0  Mask:255.255.0.0
          inet6 addr: fe80::42:fbff:fe53:2756/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:3521 errors:0 dropped:0 overruns:0 frame:0
          TX packets:3512 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:178318 (178.3 KB)  TX bytes:226978 (226.9 KB)

vagrant@tutorial-node1:~$ ifconfig eth1
eth1      Link encap:Ethernet  HWaddr 08:00:27:f7:17:75  
          inet addr:192.168.2.10  Bcast:0.0.0.0  Mask:255.255.255.0
          inet6 addr: fe80::a00:27ff:fef7:1775/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:219585 errors:0 dropped:0 overruns:0 frame:0
          TX packets:272864 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:21413163 (21.4 MB)  TX bytes:28556948 (28.5 MB)

vagrant@tutorial-node1:~$ ifconfig eth0
eth0      Link encap:Ethernet  HWaddr 08:00:27:a2:bc:0d  
          inet addr:10.0.2.15  Bcast:10.0.2.255  Mask:255.255.255.0
          inet6 addr: fe80::a00:27ff:fea2:bc0d/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:28103 errors:0 dropped:0 overruns:0 frame:0
          TX packets:13491 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:36213596 (36.2 MB)  TX bytes:858264 (858.2 KB)
```

In the above output, you'll see:
- `docker0` interface corresponds to the linux bridge and its associated
subnet `172.17.0.1/16`. This is created by docker daemon automatically, and
is the default network containers would belong to when an override network
is not specified
- `eth0` in this VM is the management interface, on which we ssh into the VM
- `eth1` in this VM is the interface that connects to external network (if needed)
- `eth2` in this VM is the interface that carries vxlan and control (e.g. etcd) traffic

```
vagrant@tutorial-node1:~$ netctl version
```
`netctl` is a utility to create, update, read and modify contiv objects. It is a CLI wrapper
on top of REST interface.

#### How to restart if VM is shut down, restarted or connectivity is lost
It is okay to restart the tutorial from where you left at the beginning of the chapter.
The recommended way is to cleanup the setup using `vagrant -f destroy`, and 
then restarting them again using `vagrant up`


### Chapter 1 - Introduction to Container Networking

There are two main container networking model discussed within the community.

#### Docker libnetwork - Container Network Model (CNM)

CNM (Container Network Model) is Docker's libnetwork network model for containers
- An endpoint is container's interface into a network
- A network is collection of arbitrary endpoints
- A container can belong to multiple endpoints (and therefore multiple networks)
- CNM allows for co-existence of multiple drivers, with a network managed by one driver
- Provides Driver APIs for IPAM and Endpoint creation/deletion
- IPAM Driver APIs: Create/Delete Pool, Allocate/Free IP Address
- Network Driver APIs: Network Create/Delete, Endpoint Create/Delete/Join/Leave
- Used by docker engine, docker swarm, and docker compose; and other schedulers
that schedules regular docker containers e.g. Nomad or Mesos docker containerizer

#### CoreOS CNI - Container Network Interface (CNI)
CNI (Container Network Interface) CoreOS's network model for containers
- Allows specifying container id (uuid) for which network interface is being created
- Provide Container Create/Delete events
- Provides access to network namespace to the driver to plumb networking
- No separate IPAM Driver: Container Create returns the IAPM information along with other data
- Used by Kubernetes and thus supported by various kubernet network plugins, including Contiv

Using Contiv with CNI/Kubernetes can be found [here](https://github.com/contiv/netplugin/tree/master/mgmtfn/k8splugin).
The rest of the tutorial walks through the docker examples, which implements CNM APIs

#### Basic container networking

Let's examine the networking a container gets upon vanilla run
```
vagrant@tutorial-node1:~$ docker network ls
NETWORK ID          NAME                DRIVER
4e8800b4788f        bridge              bridge              
ce3dd3b5e270        host                host                
0e7681adac20        none                null             

vagrant@tutorial-node1:~$ docker run -itd --name=vanilla-c alpine /bin/sh
Unable to find image 'alpine:latest' locally
latest: Pulling from library/alpine
b66121b7b9c0: Pull complete 
Digest: sha256:9cacb71397b640eca97488cf08582ae4e4068513101088e9f96c9814bfda95e0
Status: Downloaded newer image for alpine:latest
2cf083c0a4de1347d8fea449dada155b7ef1c99f1f0e684767ae73b3bbb6b533
 
vagrant@tutorial-node1:~$ ifconfig 
```

In the `ifconfig` output, you will see that it would have created a veth `virtual 
ethernet interface` that could look like `veth......` towards the end. More 
importantly it is allocated an IP address from default docker bridge `docker0`, 
likely `172.17.0.3` in this setup, and can be examined using
```
$ docker network inspect bridge
[
    {
        "Name": "bridge",
        "Id": "4e8800b4788fd21f258d3aa2f4858908b482cefe728106ab92083e604bab8728",
        "Scope": "local",
        "Driver": "bridge",
        "EnableIPv6": false,
        "IPAM": {
            "Driver": "default",
            "Options": null,
            "Config": [
                {
                    "Subnet": "172.17.0.0/16",
                    "Gateway": "172.17.0.1"
                }
            ]
        },
        "Internal": false,
        "Containers": {
            "39d6c7fa38486a22405c0bb68bffbd7831deb94c690b7353dfd34be97b532a33": {
                "Name": "vanilla-c",
                "EndpointID": "a0697a4aebe2d3ff3c4214b60c8bfaacf8f453670445899822a91b65888a8d01",
                "MacAddress": "02:42:ac:11:00:05",
                "IPv4Address": "172.17.0.5/16",
                "IPv6Address": ""
            },
            "5999ee4484bfd5270b0b22858090135447f2a3175d07d52f1aad6d0073726b77": {
                "Name": "defaultdns",
                "EndpointID": "efbc1c091c6f92b8f68c4053c00c3e383f9bce1dc37fea0fb20970d633c3c6fd",
                "MacAddress": "02:42:ac:11:00:02",
                "IPv4Address": "172.17.0.2/16",
                "IPv6Address": ""
            },
            "ddc0a899164e1d23a62d5ac312f1301bd1586180b1e82175421f2af4e783115d": {
                "Name": "swarm-manager",
                "EndpointID": "c9a353d8c1116f86197edcece771c94a197cf4fb8084d6a1243b8a46f2320708",
                "MacAddress": "02:42:ac:11:00:03",
                "IPv4Address": "172.17.0.3/16",
                "IPv6Address": ""
            },
            "fad30ce6a9658a581306bb7bfc6ea71827810294d97fd77a687a7e86739f9c42": {
                "Name": "swarm-agent",
                "EndpointID": "a24b1c59500f60c8a19821076b8a3869141452f7e493339b715ce42cf537c6c3",
                "MacAddress": "02:42:ac:11:00:04",
                "IPv4Address": "172.17.0.4/16",
                "IPv6Address": ""
            }
        },
        "Options": {
            "com.docker.network.bridge.default_bridge": "true",
            "com.docker.network.bridge.enable_icc": "true",
            "com.docker.network.bridge.enable_ip_masquerade": "true",
            "com.docker.network.bridge.host_binding_ipv4": "0.0.0.0",
            "com.docker.network.bridge.name": "docker0",
            "com.docker.network.driver.mtu": "1500"
        },
        "Labels": {}
    }
]

vagrant@tutorial-node1:~$ docker inspect --format '{{.NetworkSettings.IPAddress}}' vanilla-c
172.17.0.5
```

The other pair of veth interface is put into the container with the name `eth0`
```
vagrant@tutorial-node1:~$ docker exec -it vanilla-c /bin/sh
/ # ifconfig eth0
eth0      Link encap:Ethernet  HWaddr 02:42:AC:11:00:03  
          inet addr:172.17.0.3  Bcast:0.0.0.0  Mask:255.255.0.0
          inet6 addr: fe80::42:acff:fe11:3%32577/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:8 errors:0 dropped:0 overruns:0 frame:0
          TX packets:8 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:648 (648.0 B)  TX bytes:648 (648.0 B)
/ # exit
```

All traffic to/from this container is Port-NATed to the host's IP (on eth0).
The Port NATing on the host is done using iptables, which can be seen as a
MASQUERADE rule for outbound traffic for `172.17.0.0/16`
```
$ vagrant@tutorial-node1:~$ sudo iptables -t nat -L -n
```

### Chapter 2: Multi-host networking

There are many solutions, like Contiv, Calico, Weave, Openshift, OpenContrail, Nuage,
VMWare, Docker, Kubernetes, Openstack that provide solutions to multi-host
container networking. In this section we examine Contiv and Docker overlay solutions.

#### Multi-host networking with Contiv
Let's use the same example as above to spin up two containers on the two different hosts

3#### 1. Create a multi-host network
```
vagrant@tutorial-node1:~$ netctl net create --subnet=10.1.2.0/24 contiv-net
vagrant@tutorial-node1:~$ netctl net ls
Tenant   Network     Nw Type  Encap type  Packet tag  Subnet       Gateway
------   -------     -------  ----------  ----------  -------      ------
default  contiv-net  data     vxlan       0           10.1.2.0/24  

vagrant@tutorial-node1:~$ $ docker network ls
NETWORK ID          NAME                DRIVER
4e8800b4788f        bridge              bridge              
eeb59152fb69        contiv-net          netplugin           
ce3dd3b5e270        host                host                
0e7681adac20        none                null       

vagrant@tutorial-node1:~$ docker network inspect contiv-net
[
    {
        "Name": "contiv-net",
        "Id": "af2ed043730432e383bbe7fc7716cdfee87246f96342a320ef5fa99f8cf60312",
        "Scope": "global",
        "Driver": "netplugin",
        "IPAM": {
            "Driver": "netplugin",
            "Config": [
                {
                    "Subnet": "10.1.2.0/24"
                }
            ]
        },
        "Containers": {
            "ab353464b4e20b0267d6a078e872fd21730242235667724a9147fdf278a03220": {
                "EndpointID": "5d1720e71e3a4c8da6a8ed361480c094aeb6a3cd3adfe0c7b185690bc64ddcd9",
                "MacAddress": "",
                "IPv4Address": "10.1.2.2/24",
                "IPv6Address": ""
            }
        },
        "Options": {
            "encap": "vxlan",
            "pkt-tag": "1",
            "tenant": "default"
        }
    }
]
```

We can now run a new container belonging to `contiv-net` network that we created just now
```
vagrant@tutorial-node1:~$ docker run -itd --name=contiv-c1 --net=contiv-net alpine /bin/sh
46e619b0b418107114e93f9814963d5c351835624e8da54100b0707582c69549
```

Let's ssh into the second node using `vagrant ssh tutorial-node2`, and spin up a 
new container on it and try to reach another container running on `tutorial-node1`

```
vagrant@tutorial-node2:~$ docker run -itd --name=contiv-c2 --net=contiv-net alpine /bin/sh
26b9f22b9790b55cdfc85f1c2779db5d5fc78c18fee1ea088b85ec0883361a72

vagrant@tutorial-node2:~$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS                  PORTS               NAMES
26b9f22b9790        alpine              "/bin/sh"           2 seconds ago       Up Less than a second                       contiv-c2

vagrant@tutorial-node2:~$ docker exec -it contiv-c2 /bin/sh

/ # ping contiv-c1
PING contiv-c1 (10.1.2.3): 56 data bytes
64 bytes from 10.1.2.3: seq=0 ttl=64 time=6.596 ms
64 bytes from 10.1.2.3: seq=1 ttl=64 time=9.451 ms
^C
--- contiv-c1 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 6.596/8.023/9.451 ms

/ # exit
```
As you will see during the ping that, built in dns resolves the name `contiv-c1`
to the IP address of `contiv-c1` container and be able to reach another container
across using a vxlan overlay.


#### Docker Overlay multi-host networking

Docker engine has a built in overlay driver that can be use to connect
containers across multiple nodes. However since vxlan port used by `contiv`
driver is same as that of `overlay` driver from Docker, we will use
Docker's overlay multi-host networking towards the end after we experiment
with `contiv` because then we can terminate the contiv driver and
let Docker overlay driver use the vxlan port bindings. More about it in
later chapter.

For this experiment we switch back
to `tutorial-node1` 
```
vagrant@tutorial-node1:~$ docker network create -d=overlay --subnet=10.1.1.0/24 overlay-net
22f79fe02239d3cbc2c8a4f7147f0e799dc13f3af6e46a69cc3adf8f299a7e56

vagrant@tutorial-node1:~$ docker network inspect overlay-net
[
    {
        "Name": "overlay-net",
        "Id": "22f79fe02239d3cbc2c8a4f7147f0e799dc13f3af6e46a69cc3adf8f299a7e56",
        "Scope": "global",
        "Driver": "overlay",
        "IPAM": {
            "Driver": "default",
            "Config": [
                {
                    "Subnet": "10.1.1.0/24"
                }
            ]
        },
        "Containers": {},
        "Options": {}
    }
]
```

Now, we can create a container that belongs to `overlay-net`
```
vagrant@tutorial-node1:~$ docker run -itd --name=overlay-c1 --net=overlay-net alpine /bin/sh
0ab717006962fb2fe936aa3c133dd27d68c347d5f239f473373c151ad4c77b28

vagrant@tutorial-node1:~$ docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' overlay-c1
10.1.1.2
```

And, we can run another container within the cluster, that belongs to the same network and 
make sure that they can reach each other.
```
vagrant@tutorial-node1:~$ docker run -itd --name=overlay-c2 --net=overlay-net alpine /bin/sh
0a6f43693361855ad56cda417b9ec63f504de4782ac82f0181fed92d803b4a30
vagrant@tutorial-node1:~$ docker ps
CONTAINER ID        IMAGE                          COMMAND             CREATED             STATUS              PORTS               NAMES
fb822eda9916        alpine                         "/bin/sh"           3 minutes ago       Up 3 minutes                            overlay-c2
0ab717006962        alpine                         "/bin/sh"           21 minutes ago      Up 21 minutes                           overlay-c1
2cf083c0a4de        alpine                         "/bin/sh"           28 minutes ago      Up 28 minutes                           vanilla-c
ab353464b4e2        skynetservices/skydns:latest   "/skydns"           33 minutes ago      Up 33 minutes       53/tcp, 53/udp      defaultdns

vagrant@tutorial-node2:~$ docker exec -it overlay-c2 /bin/sh
/ # ping overlay-c1
PING overlay-c1 (10.1.1.2): 56 data bytes
64 bytes from 10.1.1.2: seq=0 ttl=64 time=0.066 ms
64 bytes from 10.1.1.2: seq=1 ttl=64 time=0.092 ms
^C
--- overlay-c1 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.066/0.079/0.092 ms

/ # exit
```
Similar to contiv-networking, built in dns resolves the name `overlay-c1`
to the IP address of `overlay-c1` container and be able to reach another container
across using a vxlan overlay.

### Chapter 3: Using multiple tenants with arbitrary IPs in the networks

First, let's create a new tenant space
```
vagrant@tutorial-node1:~$ netctl tenant create blue
INFO[0000] Creating tenant: blue                    

vagrant@tutorial-node1:~$ netctl tenant ls 
Name     
------   
default  
blue     
```

After the tenant is created, we can create network within in tenant `blue` and run containers.
Here we chose the same subnet and network name for it.
the same subnet and same network name, that we used before
```
vagrant@tutorial-node1:~$ netctl net create -t blue --subnet=10.1.2.0/24 contiv-net
vagrant@tutorial-node1:~$ netctl net ls -t blue
Tenant  Network     Nw Type  Encap type  Packet tag  Subnet       Gateway
-/-----  -------     -------  ----------  ----------  -------      ------
blue    contiv-net  data     vxlan       0           10.1.2.0/24  
```

Next, we can run containers belonging to this tenant
```
vagrant@tutorial-node1:~$ docker run -itd --name=contiv-blue-c1 --net=contiv-net/blue alpine /bin/sh
6c7d8c0b14ec6c2c9f52468faf50444e29c4b1fa61753b75c00f033564814515

vagrant@tutorial-node1:~$ docker ps
CONTAINER ID        IMAGE                          COMMAND             CREATED             STATUS              PORTS               NAMES
6c7d8c0b14ec        alpine                         "/bin/sh"           8 seconds ago       Up 6 seconds                            contiv-blue-c1
17afcd58b8fc        skynetservices/skydns:latest   "/skydns"           6 minutes ago       Up 6 minutes        53/tcp, 53/udp      bluedns
46e619b0b418        alpine                         "/bin/sh"           11 minutes ago      Up 11 minutes                           contiv-c1
fb822eda9916        alpine                         "/bin/sh"           23 minutes ago      Up 23 minutes                           overlay-c2
0ab717006962        alpine                         "/bin/sh"           41 minutes ago      Up 41 minutes                           overlay-c1
2cf083c0a4de        alpine                         "/bin/sh"           48 minutes ago      Up 48 minutes                           vanilla-c
ab353464b4e2        skynetservices/skydns:latest   "/skydns"           53 minutes ago      Up 53 minutes       53/udp, 53/tcp      defaultdns
```

Let us run a couple of more containers in the host `tutorial-node2` that belong to the tenatn `blue`
```
vagrant@tutorial-node2:~$ docker run -itd --name=contiv-blue-c2 --net=contiv-net/blue alpine /bin/sh
521abe19d6b5b3557de6ee4654cc504af0c497a64683f737ffb6f8238ddd6454
vagrant@tutorial-node2:~$ docker run -itd --name=contiv-blue-c3 --net=contiv-net/blue alpine /bin/sh
0fd07b44d042f37069f9a2f7c901867e8fd01c0a5d4cb761123e54e510705c60
vagrant@tutorial-node2:~$ docker ps
CONTAINER ID        IMAGE               COMMAND             CREATED             STATUS              PORTS               NAMES
0fd07b44d042        alpine              "/bin/sh"           7 seconds ago       Up 5 seconds                            contiv-blue-c3
521abe19d6b5        alpine              "/bin/sh"           23 seconds ago      Up 21 seconds                           contiv-blue-c2
26b9f22b9790        alpine              "/bin/sh"           13 minutes ago      Up 13 minutes                           contiv-c2

vagrant@tutorial-node2:~$ docker network inspect contiv-net/blue
[
    {
        "Name": "contiv-net/blue",
        "Id": "4b8448967b7908cab6b3788886aaccc2748bbd85251258de3d01f64e5ee7ae68",
        "Scope": "global",
        "Driver": "netplugin",
        "IPAM": {
            "Driver": "netplugin",
            "Options": {
                "network": "contiv-net",
                "tenant": "blue"
            },
            "Config": [
                {
                    "Subnet": "10.1.2.0/24"
                }
            ]
        },
        "Containers": {
            "0fd07b44d042f37069f9a2f7c901867e8fd01c0a5d4cb761123e54e510705c60": {
                "Name": "contiv-blue-c3",
                "EndpointID": "eab5b2243199e97c29e3be310b37994e31d1203af775d80b0755adfabd52531e",
                "MacAddress": "02:02:0a:01:02:04",
                "IPv4Address": "10.1.2.4/24",
                "IPv6Address": ""
            },
            "521abe19d6b5b3557de6ee4654cc504af0c497a64683f737ffb6f8238ddd6454": {
                "Name": "contiv-blue-c2",
                "EndpointID": "916c971aa4c58c6559c4fab241981d350be15855d0527b83afe4a305f92a4bda",
                "MacAddress": "02:02:0a:01:02:03",
                "IPv4Address": "10.1.2.3/24",
                "IPv6Address": ""
            },
            "ep-3c744285620b746317391c3e27c8d745f2488fae6b23dc1ebe8b217563d2a999": {
                "Name": "bluedns",
                "EndpointID": "3c744285620b746317391c3e27c8d745f2488fae6b23dc1ebe8b217563d2a999",
                "MacAddress": "02:02:0a:01:02:01",
                "IPv4Address": "10.1.2.1/24",
                "IPv6Address": ""
            },
						"ep-6c7d8c0b14ec6c2c9f52468faf50444e29c4b1fa61753b75c00f033564814515": {
                "Name": "contiv-blue-c1",
                "EndpointID": "c974b747f666d03a9eaab36d20e14f80117328a3e720cba7d17fdf40a57eccf4",
                "MacAddress": "02:02:0a:01:02:02",
                "IPv4Address": "10.1.2.2/24",
                "IPv6Address": ""
            }
        },
        "Options": {
            "encap": "vxlan",
            "pkt-tag": "2",
            "tenant": "blue"
        },
				"Labels": {}
    }
]

vagrant@tutorial-node2:~$ docker exec -it contiv-blue-c3 /bin/sh
/ # ping contiv-blue-c1
PING contiv-blue-c1 (10.1.2.2): 56 data bytes
64 bytes from 10.1.2.2: seq=0 ttl=64 time=60.414 ms
^C
--- contiv-blue-c1 ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 60.414/60.414/60.414 ms
/ # ping contiv-blue-c2
PING contiv-blue-c2 (10.1.2.3): 56 data bytes
64 bytes from 10.1.2.3: seq=0 ttl=64 time=1.637 ms
^C
--- contiv-blue-c2 ping statistics ---
1 packets transmitted, 1 packets received, 0% packet loss
round-trip min/avg/max = 1.637/1.637/1.637 ms

/ # exit
```

### Chapter 4: Connecting containers to external networks

In this chapter, we explore ways to connect containers to the external networks

#### 1. External Connectivity using Host NATing

Docker uses the linux bridge (docker_gwbridge) based PNAT to reach out and port mappings
for others to reach to the container

```
vagrant@tutorial-node1:~$ docker exec -it contiv-c1 /bin/sh
/ # ifconfig -a
eth0      Link encap:Ethernet  HWaddr 02:02:0A:01:02:03  
          inet addr:10.1.2.3  Bcast:0.0.0.0  Mask:255.255.255.0
          inet6 addr: fe80::2:aff:fe01:203%32627/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1450  Metric:1
          RX packets:19 errors:0 dropped:0 overruns:0 frame:0
          TX packets:11 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:1534 (1.4 KiB)  TX bytes:886 (886.0 B)

eth1      Link encap:Ethernet  HWaddr 02:42:AC:12:00:04  
          inet addr:172.18.0.4  Bcast:0.0.0.0  Mask:255.255.0.0
          inet6 addr: fe80::42:acff:fe12:4%32627/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:32 errors:0 dropped:0 overruns:0 frame:0
          TX packets:27 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:5584 (5.4 KiB)  TX bytes:3344 (3.2 KiB)

lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1%32627/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)

/ # ping contiv.com
PING contiv.com (216.239.34.21): 56 data bytes
64 bytes from 216.239.34.21: seq=0 ttl=61 time=35.941 ms
64 bytes from 216.239.34.21: seq=1 ttl=61 time=38.980 ms
^C
--- contiv.com ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 35.941/37.460/38.980 ms

/ # exit
```

What you see is that container has two interfaces belonging to it:
- eth0 is reachability into the `contiv-net` 
- eth1 is reachability for container to the external world and outside
traffic to be able to reach the container `contiv-c1`. This also relies on the host's dns
resolv.conf as a default way to resolve non container IP resolution.

Similarly outside traffic can be exposed on specific ports using `-p` command. Before
we do that, let us confirm that port 9099 is not reachable from the host
`tutorial-node1`. To install `nc` netcat utility please run `sudo yum -y install nc` on node1
```
vagrant@tutorial-node1:~$ $ nc -vw 1 localhost 9099
Ncat: Version 6.40 ( http://nmap.org/ncat )
Ncat: Connection to ::1 failed: Connection refused.
Ncat: Trying next address...
Ncat: Connection refused.
```

Now we start a container that exposes tcp port 9099 out in the host.
```
vagrant@tutorial-node1:~$ docker run -itd -p 9099:9099 --name=contiv-exposed --net=contiv-net alpine /bin/sh
```

And if we re-run our `nc` utility, we'll see that 9099 is reachable.
```
vagrant@tutorial-node1:~$ nc -vw 1 localhost 9099
Ncat: Version 6.40 ( http://nmap.org/ncat )
Ncat: Connected to ::1:9099.
^C
```

This happens because docker as soon as a port is exposed, a NAT rule is installed for
the port to allow rest of the network to access the container on the specified/exposed
port. The nat rules on the host can be seen by:
```
vagrant@tutorial-node1:~$ sudo iptables -t nat -L -n
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination         
CONTIV-NODEPORT  all  --  0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
DOCKER     all  --  0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL

Chain INPUT (policy ACCEPT)
target     prot opt source               destination         

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination         
DOCKER     all  --  0.0.0.0/0           !127.0.0.0/8          ADDRTYPE match dst-type LOCAL

Chain POSTROUTING (policy ACCEPT)
target     prot opt source               destination         
MASQUERADE  all  --  172.18.0.0/16        0.0.0.0/0           
MASQUERADE  all  --  172.17.0.0/16        0.0.0.0/0           
MASQUERADE  all  --  172.20.0.0/16        0.0.0.0/0           
MASQUERADE  tcp  --  172.17.0.3           172.17.0.3           tcp dpt:2375
MASQUERADE  tcp  --  172.18.0.4           172.18.0.4           tcp dpt:9099

Chain CONTIV-NODEPORT (1 references)
target     prot opt source               destination         

Chain DOCKER (2 references)
target     prot opt source               destination         
RETURN     all  --  0.0.0.0/0            0.0.0.0/0           
RETURN     all  --  0.0.0.0/0            0.0.0.0/0           
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:2375 to:172.17.0.3:2375
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:9099 to:172.18.0.4:9099
```

#### 2. Natively connecting to the external networks

Remote drivers, like Contiv, can provide an easy way to connect to external
layer2 or layer3 networks using BGP or standard L2 access into the network.

Preferably using an BGP hand-off to the leaf/TOR, this can be done as in 
[https://github.com/contiv/demo/blob/master/net/Bgp.md], which describes how
can you use BGP with Contiv to provide native container connectivity and 
reachability to rest of the network. However for this tutorial, since we don't
have a real or simulated BGP router, we'll use some very simple native L2
connectivity to describe the power of native connectivity. This is done 
using vlan network, for example

```
vagrant@tutorial-node1:~$ netctl net create -p 112 -e vlan -s 10.1.3.0/24 contiv-vlan
vagrant@tutorial-node1:~$ netctl net ls
Tenant   Network         Nw Type  Encap type  Packet tag  Subnet       Gateway
------   -------         -------  ----------  ----------  -------      ------
default  contiv-net      data     vxlan       0           10.1.2.0/24  
default  contiv-vlan     data     vlan        112         10.1.3.0/24  
```

The allocated vlan can be used to connect any workload in vlan 112 in the network infrstructure.
The interface that connects to the outside network needs to be specified during netplugin
start, for this VM configuration it is set as `eth2`

Let's run some containers to belong to this network, one on each node. Firs one on 
`tutorial-node1`
```
vagrant@tutorial-node1:~$ docker run -itd --name=contiv-vlan-c1 --net=contiv-vlan alpine /bin/sh
4bf58874c937e242b4fc2fd8bfd6896a7719fd10475af96e065a83a2e80e9e48
```

And another one on `tutorial-node2`
```
vagrant@tutorial-node2:~$ docker run -itd --name=contiv-vlan-c2 --net=contiv-vlan alpine /bin/sh
1c463ecad8295b112a7556d1eaf35f1a8152c6b8cfcef1356d40a7b015ae9d02

vagrant@tutorial-node2:~$ docker exec -it contiv-vlan-c2 /bin/sh

/ # ping contiv-vlan-c1
PING contiv-vlan-c1 (10.1.3.4): 56 data bytes
64 bytes from 10.1.3.4: seq=0 ttl=64 time=2.431 ms
64 bytes from 10.1.3.4: seq=1 ttl=64 time=1.080 ms
64 bytes from 10.1.3.4: seq=2 ttl=64 time=1.022 ms
64 bytes from 10.1.3.4: seq=3 ttl=64 time=1.048 ms
64 bytes from 10.1.3.4: seq=4 ttl=64 time=1.119 ms
. . .
```

While this is going on `tutorial-node2`, let's run run tcpdump on eth2 on `tutorial-node`
and confirm how rx/tx packets look like on it
```
vagrant@tutorial-node1:~$ sudo tcpdump -e -i eth2 icmp
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth2, link-type EN10MB (Ethernet), capture size 262144 bytes
05:16:51.578066 02:02:0a:01:03:02 (oui Unknown) > 02:02:0a:01:03:04 (oui Unknown), ethertype 802.1Q (0x8100), length 102: vlan 112, p 0, ethertype IPv4, 10.1.3.2 > 10.1.3.4: ICMP echo request, id 2816, seq 294, length 64
05:16:52.588159 02:02:0a:01:03:02 (oui Unknown) > 02:02:0a:01:03:04 (oui Unknown), ethertype 802.1Q (0x8100), length 102: vlan 112, p 0, ethertype IPv4, 10.1.3.2 > 10.1.3.4: ICMP echo request, id 2816, seq 295, length 64
05:16:53.587408 02:02:0a:01:03:02 (oui Unknown) > 02:02:0a:01:03:04 (oui Unknown), ethertype 802.1Q (0x8100), length 102: vlan 112, p 0, ethertype IPv4, 10.1.3.2 > 10.1.3.4: ICMP echo request, id 2816, seq 296, length 64
05:16:54.587550 02:02:0a:01:03:02 (oui Unknown) > 02:02:0a:01:03:04 (oui Unknown), ethertype 802.1Q (0x8100), length 102: vlan 112, p 0, ethertype IPv4, 10.1.3.2 > 10.1.3.4: ICMP echo request, id 2816, seq 297, length 64
ç05:16:55.583786 02:02:0a:01:03:02 (oui Unknown) > 02:02:0a:01:03:04 (oui Unknown), ethertype 802.1Q (0x8100), length 102: vlan 112, p 0, ethertype IPv4, 10.1.3.2 > 10.1.3.4: ICMP echo request, id 2816, seq 298, length 64
^C
5 packets captured
```

Note that the vlan shown in tcpdump is same (i.e. `112`) as what we configured in the VLAN. After verifying this, feel free to stop the ping that is still running on 
`contiv-vlan-c2` container.

### Chapter 5: Applying policies between containers with Contiv

Contiv provide a way to apply isolation policies between containers groups.
For this, we create a simple policy called db-policy, and add some rules to which ports are allowed.

Let's start with `tutorial-node1` and create the contiv-net if you start this chapter
afresh i.e. after `vagrant up`
```
vagrant@tutorial-node1:~$ netctl net create --subnet=10.1.2.0/24 contiv-net
```

Next we create a policy called `db-policy` to be applied to all db containers.
```
vagrant@tutorial-node1:~$ netctl policy create db-policy
INFO[0000] Creating policy default:db-policy
vagrant@tutorial-node1:~$ netctl policy ls
Tenant   Policy
------   ------
default  db-policy
```

Next we create some rules that are part of the policy
```
vagrant@tutorial-node1:~$ netctl policy rule-add db-policy 1 -direction=in -protocol=tcp -action=deny
vagrant@tutorial-node1:~$ netctl policy rule-add db-policy 2 -direction=in -protocol=tcp -port=8888 -action=allow -priority=10
vagrant@tutorial-node1:~$ netctl policy rule-ls db-policy
Incoming Rules:
Rule  Priority  From EndpointGroup  From Network  From IpAddress  Protocol  Port  Action
----  --------  ------------------  ------------  ---------       --------  ----  ------
1     1                                                           tcp       0     deny
2     10                                                          tcp       8888  allow
Outgoing Rules:
Rule  Priority  To EndpointGroup  To Network  To IpAddress  Protocol  Port  Action
----  --------  ----------------  ----------  ---------     --------  ----  ------
```

Finally, we associate the policy with a group (a group is an arbitrary collection of 
containers) and run some containers that belong to `db` group
```
vagrant@tutorial-node1:~$ netctl group create contiv-net db -policy=db-policy
vagrant@tutorial-node1:~$ netctl group ls
Tenant   Group  Network     Policies
------   -----  -------     --------
default  db     contiv-net  db-policy

vagrant@tutorial-node1:~$ docker run -itd --name=contiv-db --net=db alpine /bin/sh
27eedc376ef43e5a5f3f4ede01635d447b1a0c313cca4c2a640ba4d5dea3573a
```

Now let's verify this policy; in order to do so, we'll start `netcat` utility to listen an
arbitrary port within a container that belongs to `db` group. Then, from another container we
would scan a range of ports and confirm that only the one permitted i.e. `port 8888` by 
`db` policy is accessible towards db container
```
vagrant@tutorial-node1:~$ docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' contiv-db
10.1.2.7

vagrant@tutorial-node1:~$ docker exec -it contiv-db /bin/sh
/ # nc -l 8888
<awaiting connection>
```

Switch over to `tutorial-node2` window and run a web container and verify the policy. In doing so
please make sure that you enter the IP address of the node discovered above, which in our case was `10.1.2.7`
```
vagrant@tutorial-node2:~$ docker run -itd --name=contiv-web --net=contiv-net alpine /bin/sh
54108c756699071d527a567f9b5d266284aaf5299b888d75cd19ba1a40a1135a
vagrant@tutorial-node2:~$ docker exec -it contiv-web /bin/sh

/ # nc -nzvw 1 10.1.2.7 8890
nc: 10.1.2.7 (10.1.2.7:8890): Operation timed out
/ # nc -nzvw 1 10.1.2.7 8889
nc: 10.1.2.7 (10.1.2.7:8889): Operation timed out
/ # nc -nzvw 1 10.1.2.7 8888
/ #
```

Note that the last scan on port `8888` using `nc -nzvw 1 10.1.2.7 8888` returned
without any `Operation timed out` message. At this point you can add/delete rules
to the policy dynamically


### Chapter 6: Running containers in a swarm cluster

We can bring in swarm scheduler by redirecting our requests to an already provision
swarm cluster. To do so, we can set `DOCKER_HOST` as follows:
```
vagrant@tutorial-node1:~$ export DOCKER_HOST=tcp://192.168.2.10:2375
```

Let's look at the status of various hosts using `docker info`
```
vagrant@tutorial-node1:~$ docker info
Containers: 16
Images: 3
Role: primary
Strategy: spread
Filters: health, port, dependency, affinity, constraint
Nodes: 2
 tutorial-node1: 192.168.2.10:2385
  └ Containers: 10
  └ Reserved CPUs: 0 / 4
  └ Reserved Memory: 0 B / 2.051 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.0.0-040000-generic, operatingsystem=Ubuntu 15.04, storagedriver=overlay
 tutorial-node2: 192.168.2.11:2385
  └ Containers: 6
  └ Reserved CPUs: 0 / 4
  └ Reserved Memory: 0 B / 2.051 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.0.0-040000-generic, operatingsystem=Ubuntu 15.04, storagedriver=overlay
CPUs: 8
Total Memory: 4.103 GiB
Name: tutorial-node1
No Proxy: 192.168.2.10,192.168.2.11,127.0.0.1,localhost,netmaster
```

Above command would display the #nodes, #containers in the cluster, available cpu,
memory and other relevant details.

At this point if we run some containers, they will get schedule dynamically across 
the cluster, which is two nodes `tutorial-node1` and `tutorial-node2` for us.
To see the node on where the containers get scheduled, we can use `docker ps` command
```
vagrant@tutorial-node1:~$ docker run -itd --name=contiv-cluster-c1 --net=contiv-net alpine /bin/sh
f8fa35c0aa0ecd692a31e3d5249f5c158bd18902926978265acb3b38a9ed1c0d
vagrant@tutorial-node1:~$ docker run -itd --name=contiv-cluster-c2 --net=contiv-net alpine /bin/sh
bfc750736007c307827ae5012755085ca6591f3ac3ac0b707d2befd00e5d1621
```

After running two containers, scheduler will schedule these containers using the
scheduling algorithm `bin-packing` or `spread`, and if they are not placed on 
different nodes, feel free to start more containers to see the distribution.

```
vagrant@tutorial-node1:~$ docker ps
CONTAINER ID        IMAGE                          COMMAND             CREATED             STATUS                  PORTS                         NAMES
bfc750736007        alpine                         "/bin/sh"           5 seconds ago       Up Less than a second                                 tutorial-node2/contiv-cluster-c2
f8fa35c0aa0e        alpine                         "/bin/sh"           22 seconds ago      Up 16 seconds                                         tutorial-node2/contiv-cluster-c1
54108c756699        alpine                         "/bin/sh"           14 minutes ago      Up 14 minutes                                         tutorial-node2/contiv-web
27eedc376ef4        alpine                         "/bin/sh"           25 minutes ago      Up 25 minutes                                         tutorial-node1/contiv-db
1c463ecad829        alpine                         "/bin/sh"           39 minutes ago      Up 39 minutes                                         tutorial-node2/contiv-vlan-c2
4bf58874c937        alpine                         "/bin/sh"           40 minutes ago      Up 40 minutes                                         tutorial-node1/contiv-vlan-c1
52bfcc02c362        alpine                         "/bin/sh"           About an hour ago   Up About an hour        192.168.2.10:9099->9099/tcp   tutorial-node1/contiv-exposed
0fd07b44d042        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                      tutorial-node2/contiv-blue-c3
521abe19d6b5        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                      tutorial-node2/contiv-blue-c2
6c7d8c0b14ec        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                            tutorial-node1/contiv-blue-c1
17afcd58b8fc        skynetservices/skydns:latest   "/skydns"           2 hours ago         Up 2 hours              53/tcp, 53/udp                tutorial-node1/bluedns
26b9f22b9790        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                            tutorial-node2/contiv-c2
46e619b0b418        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                            tutorial-node1/contiv-c1
fb822eda9916        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                            tutorial-node1/overlay-c2
0ab717006962        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                            tutorial-node1/overlay-c1
2cf083c0a4de        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                            tutorial-node1/vanilla-c
ab353464b4e2        skynetservices/skydns:latest   "/skydns"           2 hours ago         Up 2 hours              53/tcp, 53/udp                tutorial-node1/defaultdns
```

Let us conclude this section by checking the inter-container connectivity and external 
connectivity for the containers scheduled across multiple hosts
```
agrant@tutorial-node1:~$ docker exec -it contiv-cluster-c1 /bin/sh
/ # 
/ # 
/ # 
/ # ping contiv-cluster-c2
PING contiv-cluster-c2 (10.1.2.7): 56 data bytes
64 bytes from 10.1.2.7: seq=0 ttl=64 time=8.440 ms
64 bytes from 10.1.2.7: seq=1 ttl=64 time=1.479 ms
^C
--- contiv-cluster-c2 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 1.479/4.959/8.440 ms
/ # ping contiv.com
PING contiv.com (216.239.36.21): 56 data bytes
64 bytes from 216.239.36.21: seq=0 ttl=61 time=43.537 ms
64 bytes from 216.239.36.21: seq=1 ttl=61 time=38.867 ms
^C
--- contiv.com ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 38.867/41.202/43.537 ms
```

#### Chapter 6: Docker Overlay multi-host networking

As we learned earlier that use vxlan port conflict can prevent us from using
Docker `overlay` network. For us to experiment with this, we'd go ahead
and terminat `contiv` driver first on both nodes i.e. `tutorial-node1` and
`tutorial-node2`

```
[vagrant@tutorial-node2 ~]$ ps aux | grep "/opt/bin/netplugin"
vagrant   4227  0.0  0.0 113124  1592 ?        Ss   10:51   0:00 bash -c sudo /opt/bin/netplugin -plugin-mode docker -vlan-if eth2 -cluster-store etcd://localhost:2379 > /tmp/netplugin.log 2>&1
root      4238  0.0  0.1 193436  2784 ?        S    10:51   0:00 sudo /opt/bin/netplugin -plugin-mode docker -vlan-if eth2 -cluster-store etcd://localhost:2379
root      4239  0.5  1.1 576804 21168 ?        Sl   10:51   3:02 /opt/bin/netplugin -plugin-mode docker -vlan-if eth2 -cluster-store etcd://localhost:2379
vagrant  12966  0.0  0.0 112652   980 pts/2    R+   20:03   0:00 grep --color=auto /opt/bin/netplugin
[vagrant@tutorial-node2 ~]$ sudo kill -9 4239
[vagrant@tutorial-node2 ~]$ ps aux | grep "/opt/bin/netplugin"
vagrant  12973  0.0  0.0 112648   980 pts/2    R+   20:03   0:00 grep --color=auto /opt/bin/netplugin
```

To try out overlay driver, we switch to `tutorial-node1` and create an overlay network first.
```
vagrant@tutorial-node1:~$ docker network create -d=overlay --subnet=30.1.1.0/24 overlay-net
22f79fe02239d3cbc2c8a4f7147f0e799dc13f3af6e46a69cc3adf8f299a7e56

vagrant@tutorial-node1:~$ docker network inspect overlay-net
[
    {
        "Name": "overlay-net",
        "Id": "22f79fe02239d3cbc2c8a4f7147f0e799dc13f3af6e46a69cc3adf8f299a7e56",
        "Scope": "global",
        "Driver": "overlay",
        "IPAM": {
            "Driver": "default",
            "Config": [
                {
                    "Subnet": "30.1.1.0/24"
                }
            ]
        },
        "Containers": {},
        "Options": {}
    }
]
```

Now, we can create few containers that belongs to `overlay-net`, which can get scheduled
on any of the available nodes by the scheduler. Note that we still have DOCKER_HOST set to point
to the swarm cluster.

```
vagrant@tutorial-node1:~$ docker run -itd --name=overlay-c1 --net=overlay-net alpine /bin/sh
2cc629162e533f49901df8e1ea47dc1d26076abe65ca34188ce56ba3feb65118

vagrant@tutorial-node1:~$ docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' overlay-c1
30.1.1.2

[vagrant@tutorial-node1 ~]$ docker run -itd --name=overlay-c2 --net=overlay-net alpine /bin/sh
db1fb99d99abc53ad2403f538c8b7919b363bfd7beab0e137b3cef72a097c239

[vagrant@tutorial-node1 ~]$ docker run -itd --name=overlay-c3 --net=overlay-net alpine /bin/sh
29faca64211eb41efff5dc2d717d0c21006b450bbaa4f40819debd76e8a81f0e

[vagrant@tutorial-node1 ~]$ docker ps
CONTAINER ID        IMAGE                          COMMAND             CREATED             STATUS              PORTS                         NAMES
29faca64211e        alpine                         "/bin/sh"           4 minutes ago       Up 4 minutes                                      tutorial-node2/overlay-c3
db1fb99d99ab        alpine                         "/bin/sh"           43 minutes ago      Up 43 minutes                                     tutorial-node2/overlay-c2
2cc629162e53        alpine                         "/bin/sh"           51 minutes ago      Up 51 minutes                                     tutorial-node2/overlay-c1
27562283daee        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node2/contiv-cluster-c2
7ef719672f74        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node2/contiv-cluster-c1
75f32a4ca91a        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node2/contiv-web
47da958fa310        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node1/contiv-db
9dbafcbfabe5        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node2/contiv-vlan-c2
c011a269cc34        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node1/contiv-vlan-c1
244181b3c52d        alpine                         "/bin/sh"           About an hour ago   Up About an hour    192.168.2.10:9099->9099/tcp   tutorial-node1/contiv-exposed
3b8ec5f2a677        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node2/contiv-blue-c3
d05ea4cae931        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node2/contiv-blue-c2
2fa04bec0b73        alpine                         "/bin/sh"           About an hour ago   Up About an hour                                  tutorial-node1/contiv-blue-c1
f2e3adbf62e1        skynetservices/skydns:latest   "/skydns"           About an hour ago   Up About an hour    53/tcp, 53/udp                tutorial-node1/bluedns
17fc681fc3f7        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                        tutorial-node1/contiv-c1
39d6c7fa3848        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                        tutorial-node1/vanilla-c
e8afe4a2d051        alpine                         "/bin/sh"           2 hours ago         Up 2 hours                                        tutorial-node2/contiv-c2
5999ee4484bf        skynetservices/skydns:latest   "/skydns"           2 days ago          Up 2 days           53/tcp, 53/udp                tutorial-node1/defaultdns

vagrant@tutorial-node2:~$ docker exec -it overlay-c2 /bin/sh
/ # ping overlay-c1
PING overlay-c1 (10.1.1.2): 56 data bytes
64 bytes from 10.1.1.2: seq=0 ttl=64 time=0.066 ms
64 bytes from 10.1.1.2: seq=1 ttl=64 time=0.092 ms
^C
--- overlay-c1 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.066/0.079/0.092 ms

/ # exit
```
Very similar to contiv-networking, built in dns resolves the name `overlay-c1`
to the IP address of `overlay-c1` container and be able to reach another container
across using a vxlan overlay.

### Cleanup: **after all play is done**
To cleanup the setup, after doing all the experiments, exit the VM destroy VMs
```
$ vagrant destroy -f
==> tutorial-node2: Forcing shutdown of VM...
==> tutorial-node2: Destroying VM and associated drives...
==> tutorial-node1: Forcing shutdown of VM...
==> tutorial-node1: Destroying VM and associated drives...
```

### References
1. [CNI Specification](https://github.com/containernetworking/cni/blob/master/SPEC.md)
2. [CNM Design](https://github.com/docker/libnetwork/blob/master/docs/design.md)
3. [Contiv User Guide](http://docs.contiv.io)
4. [Contiv Networking Code](https://github.com/contiv/netplugin)


### Improvements or Comments
This tutorial was developed by Contiv engineers. Thank you for trying out this tutorial.
Please file a github issue if you see an issue with the tutorial, or if you prefer
improving some text, feel free to send a pull request.
