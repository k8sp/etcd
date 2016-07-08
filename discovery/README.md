# etcd 机群和 Discovery

在这个试验里，我们启动一个有四个node的Vagrant虚拟机群。我们在其中第一个node上运行一个单进程的etcd机群，用它作为discovery service，来在剩下三个nodes上启动一个三进程的etcd机群。

  * [Vagrant 虚拟机群](#vagrant-虚拟机群)
  * [单进程etcd机群](#单进程etcd机群)
  * [Pitfalls](#pitfalls)
    * [在Docker里运行etcd](#在docker里运行etcd)
    * [Don't Use CoreOS's etcd](#dont-use-coreoss-etcd)


## Vagrant 虚拟机群

CoreOS提供了一个[Github repo](https://github.com/coreos/coreos-vagrant)来配置一个简单的CoreOS虚拟机群。我们用它来启动一个四个node的虚拟机群。

```
git clone https://github.com/coreos/coreos-vagrant
cd coreos-vagrant
```

编辑 `Vagrantfile`，引入几个修改：

1. `$update_channel = "alpha"` 改成 `$update_channel = "stable"`
1. `$num_instances = 1` 改成 `$num_instances = 6`，这样机群里有6个nodes。
1. `$vm_memory = 1024` 改成 `$vm_memory = 2048`，这样每个node有2GB内存。

这样我们就可以启动机群了：

```
vagrant up
vagrant status
```

我们可以用以下命令查看每个虚拟机的eth1网卡的IP地址：

```
for ((i = 1; i <= 6; i++ )); do vagrant ssh core-0$i -c "ifconfig eth1"; done
```

应该看到IP地址从`172.17.8.101`到`172.17.8.106`。



## 单进程etcd机群

### 在host上运行

我们在任何一台虚拟机上启动一个单进程的etcd机群很容易：

```
vagrant ssh core-04
etcd2
```

在另一个terminal里可以运行

```
etcdctl ls /
```

来连接本机的 etcd2 进程。注意 `etcdctl ls /`相当于`etcdctl --endpoints=127.0.0.1:4001,127.0.0.1:2379 ls /`。

CoreOS里 `/usr/bin/etcd2` 和 `/usr/bin/etcdctl` 的版本是一致的，而 `/usr/bin/etcd` 通常是一个很老的版本。

### 在container里运行

我们也可以通过 Docker 启动一个对应版本的 etcd container：

```
docker run \
  --net=host \
  --name learn-etcd \
  --rm quay.io/coreos/etcd:v2.3.1
```

或者

```
docker run \
  -p 127.0.0.1:4001:4001 \
  -p 127.0.0.1:7001:7001 \
  -p 127.0.0.1:2379:2379 \
  -p 127.0.0.1:2380:2380 \
  --name learn-etcd \
  --rm quay.io/coreos/etcd:v2.3.1
```

对应的，也可以在 container 里运行 etcdctl：

```
docker exec learn-etcd /etcdctl ls /
```


### 让其他机器可以访问

etcd的默认命令行参数是把和peer通信的port以及和client通信的port都绑定在127.0.0.1上的。所以只有在本机上可以用etcdctl访问etcd服务。为了让其他机器上的程序也能访问本机上的etcd服务，我们需要把ports绑定在本机网卡对应的IP地址上。比如我们在core-04上执行以下命令：

```
THIS_IP=$(ifconfig | grep 172.17.8. | awk '{print $2;}')
etcd2 --name boot01 \
--initial-advertise-peer-urls http://$THIS_IP:2380 \
--listen-peer-urls http://$THIS_IP:2380 \
--listen-client-urls http://$THIS_IP:2379,http://127.0.0.1:2379 \
--advertise-client-urls http://$THIS_IP:2379 \
--initial-cluster-token bootstrap \
--initial-cluster boot01=http://$THIS_IP:2380 \
--initial-cluster-state new
```

随后可以在其他任何一台机器上用etcdctl访问：

```
etcdctl --endpoints=http://172.17.8.104:2379,http://172.17.8.104:4001 ls /
```


## 多进程机群

### 固定大小明确IP

上面例子可以拓展到配置一个（比如三个节点的）etcd机群。打开3个terminal，在每一个terminal里登陆到一台虚拟机，比如在第一个terminal里执行 `vagrant ssh core-01`。重复三次之后就ssh到三台虚拟机上了。在每个terminal窗口里输入以下同一组命令：

```
CLUSTER="etcd1=http://172.17.8.101:2380,etcd2=http://172.17.8.102:2380,etcd3=http://172.17.8.103:2380"
THIS_IP=$(ifconfig | grep 172.17.8. | awk '{print $2;}')
INDEX=$(echo $THIS_IP | tail -c 2)
etcd2 --name etcd$INDEX \
  --initial-advertise-peer-urls http://$THIS_IP:2380 \
  --listen-peer-urls http://$THIS_IP:2380 \
  --listen-client-urls http://$THIS_IP:2379,http://127.0.0.1:2379 \
  --advertise-client-urls http://$THIS_IP:2379 \
  --initial-cluster-token etcd-cluster-1 \
  --initial-cluster $CLUSTER \
  --initial-cluster-state new
```

然后登陆到 core-04 上验证往一个节点里写的内容可以从其他节点读出来：

```
vagrant ssh core-04
core@core-04 ~ $ etcdctl --endpoints=http://172.17.8.101:2379 ls /
core@core-04 ~ $ etcdctl --endpoints=http://172.17.8.101:2379 set /foo bar
bar
core@core-04 ~ $ etcdctl --endpoints=http://172.17.8.101:2379 get /foo
bar
core@core-04 ~ $ etcdctl --endpoints=http://172.17.8.102:2379 get /foo
bar
core@core-04 ~ $ etcdctl --endpoints=http://172.17.8.103:2379 get /foo
bar
```


### 利用Discovery服务

很多时候，我们并不能提前知道host的IP地址，比如，当host都是通过DHCP获取IP地址的时候。这时我们可以利用一个已经存在的etcd机群来帮助一个新机群里的members互相建立联系。原理如下：

1. 为新etcd机群标志一个uuid；
1. 在已有etcd机群里创建一个以这个uuid为名字的directory；
1. 启动新机群的etcd members的时候，通过命令行参数告诉它们这个uuid；
1. 新机群的etcd members都可以向已有etcd机群的这个uuid里注册自己的信息，从而互相找到。

这里有一个细节，我们在已有机群里写uuid的时候，也写入我们期待的新etcd机群里的members数量。这样如果有超出members数量的etcd进程注册自己，这些多余的etcd进程就成为新机群的 proxy，而不是members。

接下来我们来验证一下这套机制：

1. 首先，按照[上面例子](#让其他机器可以访问)，在 core-01 上启动一个单节点的etcd机群。

2. 然后，我们利用这个小机群在 core-02 到 core-04 上启动一个有三个members的新etcd机群：

   1. 在任何一台机器上（Linux或者MacOSX），运行`uuidgen`可以得到一个uuid。比如 `8D527FB2-B3CB-4FDB-A70A-AF35E38D5A80`。

   1. 在老etcd机群里创建一个以此uuid为名字的目录，并且把期待的新etcd机群的members数量（3）写进去。为此我们可能要登录到虚拟机群里某一台机器：

      ```
      vagrant core-02
      curl -X PUT http://172.17.8.101:2379/v2/keys/discovery/8D527FB2-B3CB-4FDB-A70A-AF35E38D5A80/_config/size -d value=3
      ```

      为了验证是否写入了，我们可以执行：

      ```
      etcdctl --endpoints=http://172.17.8.101:2379 get /discovery/8D527FB2-B3CB-4FDB-A70A-AF35E38D5A80/_config/size
      ```

1. 我们在 core-02 到 core-04 上启动三个 etcd 进程，利用 core-01 上的单节点etcd机群，来帮助这三个新进程互相认识，并组成一个新etcd机群。打开三个terminal窗口，分别用`vagrant ssh`登录到上述三台虚拟机，然后在这些窗口里粘贴如下命令：

   ```
THIS_IP=$(ifconfig | grep 172.17.8. | awk '{print $2;}')
INDEX=$(echo $THIS_IP | tail -c 2)
etcd2 --name etcd$INDEX \
  --initial-advertise-peer-urls http://$THIS_IP:2380 \
  --listen-peer-urls http://$THIS_IP:2380 \
  --listen-client-urls http://$THIS_IP:2379,http://127.0.0.1:2379 \
  --advertise-client-urls http://$THIS_IP:2379 \
  --discovery http://172.17.8.101:2379/v2/keys/discovery/8D527FB2-B3CB-4FDB-A70A-AF35E38D5A80
   ```

1. 验证新机群可以工作。在core-05上执行以下命令：

   ```
core@core-05 ~ $ etcdctl --endpoints=http://172.17.8.102:2379 ls /
core@core-05 ~ $ etcdctl --endpoints=http://172.17.8.102:2379 set /foo bar
bar
core@core-05 ~ $ etcdctl --endpoints=http://172.17.8.102:2379 get /foo
bar
   ```

1. 把步骤3中的命令，在 core-05 上再粘贴一次，从而启动一个 proxy。

1. 在 core-06 上验证可以通过 core-05 上的 proxy 访问新机群：

   ```
core@core-06 ~ $ etcdctl --endpoints=http://172.17.8.105:2379 ls /
/foo
core@core-06 ~ $ etcdctl --endpoints=http://172.17.8.105:2379 get /foo
bar
   ```
  
## Pitfalls

### 在Docker里运行etcd

我本来是按照这个[tutorial](https://coreos.com/etcd/docs/latest/docker_guide.html)中的办法来启动etcd container的：

```
docker run -p 4001:4001 -p 7001:7001 -p 2379:2379 -p 2380:2380 --name learn-etcd --rm quay.io/coreos/etcd:v2.3.2
```

但是 `etcdctl ls /` 抱怨说

> Error:  read tcp 127.0.0.1:4001: connection reset by peer”

我搜到[这个页面](https://github.com/coreos/etcd/blob/master/Documentation/op-guide/container.md#docker)里介绍的方法的启发，改用`--net=host`，而不是export各个port，`etcctl -ls /`就可以工作了。

李鹏帮我分析的时候看了`netstat -lntp`的输出：
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
[讨论](https://github.com/docker/docker/issues/2174)。我采取了一种做法：在docker命令里明确指明IPv4地址格式：

```
docker run -p 127.0.0.1:4001:4001 -p 127.0.0.1:7001:7001 -p 127.0.0.1:2379:2379 -p 127.0.0.1:2380:2380 --name learn-etcd --rm quay.io/coreos/etcd:v2.3.2
```

这样一来，`netstat -lntp`的输出里显示的地址都是IPv4的形式了。但是`etcdctl`报错：

```
core@core-01 ~ $ etcdctl --endpoints=127.0.0.1:4001,127.0.0.1:2379 ls /
Error:  EOF
```

最后尝试运行Docker image里面的etcdctl，这样就OK了：

```
core@core-01 ~ $ docker exec learn-etcd /etcdctl set /foo bar
bar
```

