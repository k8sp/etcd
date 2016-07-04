\# etcd 机群和 Discovery

在这个试验里，我们启动一个有四个node的Vagrant虚拟机群。我们在其中第一个node上运行一个单进程的etcd机群，用它作为discovery service，来在剩下三个nodes上启动一个三进程的etcd机群。



## Vagrant 虚拟机群

CoreOS提供了一个[Github repo](https://github.com/coreos/coreos-vagrant)来配置一个简单的CoreOS虚拟机群。我们用它来启动一个四个node的虚拟机群。

```
git clone https://github.com/coreos/coreos-vagrant
cd coreos-vagrant
```

编辑 `Vagrantfile`，引入两个修改：

1. `$num_instances = 1` 改成 `$num_instances = 4`，这样机群里有四个nodes。
1. `$vm_memory = 1024` 改成 `$vm_memory = 2048`，这样每个node有4GB内存。

这样我们就可以启动机群了：

```
vagrant up
vagrant status
```

我们可以用以下命令查看每个虚拟机的eth1网卡的IP地址：

```
for ((i = 1; i <= 4; i++ )); do vagrant ssh core-0$i -c "ifconfig eth1"; done
```

应该看到IP地址从`172.17.8.101`到`172.17.8.104`。



## 单进程etcd机群

我们在名为 core-01 （IP地址是172.17.8.101）的虚拟机上启动一个单进程的etcd机群：

运行 `vagrant ssh core-01` 可以登录到 core-01 上。运行 `etcdctl --version`可以看到本机的etcdctl的版本。我的是`2.3.2`。接下来可以通过 Docker 启动一个对应版本的 etcd container：

```
docker run --net=host --rm --name etcd quay.io/coreos/etcd:v2.3.2
```

注意，CoreOS虽然自带etcd程序，但是不要用，因为[版本很老](#don't-use-coreos's-etcd)。关于在Docker里启动etcd，我碰到[一个问题](#在docker里运行etcd)。



## Pitfalls

### 在Docker里运行etcd

我本来是按照这个[tutorial](https://coreos.com/etcd/docs/latest/docker_guide.html)中的办法来启动etcd container的：

```
docker run -p 4001:4001 -p 7001:7001 -p 2379:2379 -p 2380:2380 --name learn-etcd --rm quay.io/coreos/etcd:v2.3.2
```

但是 `etcdctl ls /` 抱怨说

> Error:  read tcp 127.0.0.1:4001: connection reset by peer”

我搜到[这个页面](https://github.com/coreos/etcd/blob/master/Documentation/op-guide/container.md#docker)里介绍的方法的启发，改用`--net=host`，而不是export各个port，`etcctl -ls /`就可以工作了。

李鹏棒我分析的时候看了`netstat -lntp`的输出：
```
core@core-01 ~ $ netstat -lntp
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp6       0      0 :::22                   :::*                    LISTEN      -                   
tcp6       0      0 :::7001                 :::*                    LISTEN      -                   
tcp6       0      0 :::4001                 :::*                    LISTEN      -                   
tcp6       0      0 :::2379                 :::*                    LISTEN      -                   
tcp6       0      0 :::2380                 :::*                    LISTEN      -
```

可以看到，IP地址都用的是IPv6的格式。而用`docker run --net=host --rm
--name etcd quay.io/coreos/etcd:v2.3.2`的时候，IP地址都是IPv4的形式：

```
core@core-01 ~ $ netstat -lntp
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 127.0.0.1:7001          0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:4001          0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:2379          0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:2380          0.0.0.0:*               LISTEN      -                   
tcp6       0      0 :::22                   :::*                    LISTEN      -                   
```

借着这个线索，我找到这个
[讨论](https://github.com/docker/docker/issues/2174)。我采取了一种一种
做法：在docker命令里明确指明IPv4地址格式：

```
docker run -p 127.0.0.1:4001:4001 -p 127.0.0.1:7001:7001 -p 127.0.0.1:2379:2379 -p 127.0.0.1:2380:2380 --name learn-etcd --rm quay.io/coreos/etcd:v2.3.2
```

这样一来，`netstat -lntp`的输出里显示的地址都是IPv4的形式了。但是`etcdctl`报错：

```
core@core-01 ~ $ etcdctl --endpoints=127.0.0.1:4001,127.0.0.1:2379 ls /
Error:  EOF
```

### Don't Use CoreOS's etcd

不知道为什么，CoreOS自带的etcd和etcdctl的版本不一致。而且etcd的版本很
老。所以确实得用Docker运行最新的image。

```
core@core-01 ~ $ cat /etc/os-release
NAME=CoreOS
ID=coreos
VERSION=899.17.0
VERSION_ID=899.17.0
BUILD_ID=2016-05-03-2151
PRETTY_NAME="CoreOS 899.17.0"
ANSI_COLOR="1;32"
HOME_URL="https://coreos.com/"
BUG_REPORT_URL="https://github.com/coreos/bugs/issues"
core@core-01 ~ $ etcd --version
etcd version 0.4.9
core@core-01 ~ $ etcdctl --version
etcdctl version 2.2.3
```

```
core@core-01 ~ $ cat /etc/os-release 
NAME=CoreOS
ID=coreos
VERSION=1097.0.0
VERSION_ID=1097.0.0
BUILD_ID=2016-07-02-0145
PRETTY_NAME="CoreOS 1097.0.0 (MoreOS)"
ANSI_COLOR="1;32"
HOME_URL="https://coreos.com/"
BUG_REPORT_URL="https://github.com/coreos/bugs/issues"
core@core-01 ~ $ etcd --version
etcd version 0.4.9
core@core-01 ~ $ etcdctl --version
etcdctl version 2.3.2
```

```
core@core-01 ~ $ cat /etc/os-release 
NAME=CoreOS
ID=coreos
VERSION=899.17.0
VERSION_ID=899.17.0
BUILD_ID=2016-05-03-2151
PRETTY_NAME="CoreOS 899.17.0"
ANSI_COLOR="1;32"
HOME_URL="https://coreos.com/"
BUG_REPORT_URL="https://github.com/coreos/bugs/issues"
core@core-01 ~ $ etcd --version
etcd version 0.4.9
core@core-01 ~ $ etcdctl --version
etcdctl version 2.2.3
```
