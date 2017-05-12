# 玩转`etcd`

`etcd`事实上是Hadoop Zookeeper的替代。而Zookeeper是Google Chubby的开源
仿制。对Chubby的描述见
[这篇论文](http://research.google.com/archive/chubby.html)。文中说
Chubby是一个*lock service*，实际上简单的理解是Chubby是一个key-value存
储系统，和分布式文件系统（如GFS）类似，只是为了性能考虑，每个etcd维护
的文件大小尽量小于1MB。

## 文档

目前常用的etcd 版本是 2.x，和之前的 1.x有诸多不同。比如 1.x etcd监听
4001 和 7001 端口，而etcd2监听 2379 和 2380 端口。etcd2的文档在
[这里](https://github.com/coreos/etcd/tree/master/Documentation/v2)。

## 安装

etcd的Github页面的Releases列表里有[安装介绍](https://github.com/coreos/etcd/releases)。

## 单点部署

如果不考虑利用Raft协议实现不间断服务，最简单的etcd配置可以只有一个进程。
这个进程监听本机 2379 端口。我们可以用 curl 之类的标准工具和这个端口通
信——写入或者读取 key-value pairs。

下面例子下载并且启动一个etcd进程，然后利用etcdctl程序来访问这个单点部署：

```
wget -c https://github.com/coreos/etcd/releases/download/$VER/etcd-v2.3.6-darwin-amd64.zip
unzip etcd-v2.3.6-darwin-amd64.zip
ln -s etcd

(./etcd/etcd 2>&1 > ./single-node.log) &

./etcd/etcdctl set /hello Message
./etcd/etcdctl get /hello
```

上面例子里，etcd和etcdctl都使用默认端口 2379 通信。如果想使用非默认端
口，请参见下面例子：

## 多点部署

通常为了容错，也为了不间断服务，我们可以在多台机器上启动多个 etcd 进程。
每个进程可以通过本地 2379 端口和客户端程序通信，此外 etcd 进程之间通过
2380 端口互相通信和协调。如果当前主进程（*leader*）挂了，剩下的进程利
用Raft协议推举一个新的主进程。

有两种多点部署的机制：static和discovery。

### 静态集群

如果我们可以决定在哪些机器上启动etcd，以及每个etcd进程的port，那么一切
都很简单：为了让多个etcd进程互相知道对方，我们给每个进程一个命令行参数
`--initial-cluster`，用来指定etcd cluster里所有的进程，比如：

```
infra0=http://10.0.1.10:2380,infra1=http://10.0.1.11:2380,infra2=http://10.0.1.12:2380
```

其中 `infra0`, `infra1`, `infra2` 是三个etcd进程的名字，通过命令行参数
`--name`指定。

此外，还需要告诉每个etcd进程自己是其中哪一个，为此需要设置
`--initial-advertise-peer-urls`，比如：

```
--initial-advertise-peer-urls http://10.0.1.10:2380
```

关于static方式，请参见CoreOS公司的
[这篇文档](https://coreos.com/etcd/docs/latest/clustering.html#static)。

如果想在本机上启动一个三个进程的etcd 机群，可以打开三个terminal窗口，依次输入一下三个启动命令：

```
`pwd`/etcd/etcd \
    --name infra0 \
    --initial-advertise-peer-urls http://127.0.0.1:7001 \
    --listen-peer-urls http://127.0.0.1:7001 \
    --listen-client-urls http://127.0.0.1:4001 \
    --advertise-client-urls http://127.0.0.1:4001 \
    --initial-cluster-token etcd-cluster-1 \
    --initial-cluster infra0=http://127.0.0.1:7001,infra1=http://127.0.0.1:7002,infra2=http://127.0.0.1:7003 \
    --initial-cluster-state new 

`pwd`/etcd/etcd \
    --name infra1 \
    --initial-advertise-peer-urls http://127.0.0.1:7002 \
    --listen-peer-urls http://127.0.0.1:7002 \
    --listen-client-urls http://127.0.0.1:4002 \
    --advertise-client-urls http://127.0.0.1:4002 \
    --initial-cluster-token etcd-cluster-1 \
    --initial-cluster infra0=http://127.0.0.1:7001,infra1=http://127.0.0.1:7002,infra2=http://127.0.0.1:7003 \
    --initial-cluster-state new 

`pwd`/etcd/etcd \
    --name infra2 \
    --initial-advertise-peer-urls http://127.0.0.1:7003 \
    --listen-peer-urls http://127.0.0.1:7003 \
    --listen-client-urls http://127.0.0.1:4003 \
    --advertise-client-urls http://127.0.0.1:4003 \
    --initial-cluster-token etcd-cluster-1 \
    --initial-cluster infra0=http://127.0.0.1:7001,infra1=http://127.0.0.1:7002,infra2=http://127.0.0.1:7003 \
    --initial-cluster-state new 
```

这个例子里，三个etcd进程都启动在同一台机器上，所以不能使用默认的 2379
端口用于和客户通信，以及默认的 2380 端口用于etcd进程间通信。为此，第一
个进程用4001端口和客户通信，以及7001和其他etcd进程通信。类似的，第二个
进程用4002和7002，第三个用4003和7003。

需要注意的是，一个etcd机群最少需要两个进程。因为Raft协议要求要大多数进
程赞同，才能决定一个leader。而当只有两个进程的时候，Raft协议中的“大多
数”指的是2。

### 动态发现

可惜大多数时候，etcd进程是通过机群管理系统启动的，我们事先并不知道会用
到哪些机器，也不能确定每个etcd进程的port。此时我们要借助一个第三方服
务——discovery。我们可以用这套代码：
https://github.com/coreos/discovery.etcd.io ：

```
git clone https://github.com/coreos/discovery.etcd.io
cd discovery.etcd.io

go run third_party.go build github.com/coreos/discovery.etcd.io

./discovery.etcd.io --addr=:8087
```

这个discovery服务维护一个映射表，从一个机群ID到这个机群里有哪些etcd进
程。当我们创建etcd机群的时候，我们访问这个服务的`/new` URL，从而为我们
的新机群在这个映射表里增加一项，并且返回这一项的ID。比如下面命令创建一
个有三个etcd进程的机群：

```
$ curl http://localhost:8087/new?size=3
https://discovery.etcd.io/9b14ae6ce7764df5464542caface175d
```

其中`3`是我们预期的etcd进程的数量；
`9b14ae6ce7764df5464542caface175d`就是我们新机群的ID。

随后，我们就可以修改上一节例子中启动etcd进程的命令行，不再需要
`--initial-cluster`, `--initial-cluster-token`,
`--initial-cluster-state` 这些参数了，而是用 `--discovery
http://localhost:8087/9b14ae6ce7764df5464542caface175d` ：

```
$ etcd --name infra0 --initial-advertise-peer-urls http://10.0.1.10:2380 \
  --listen-peer-urls http://10.0.1.10:2380 \
  --listen-client-urls http://10.0.1.10:2379,http://127.0.0.1:2379 \
  --advertise-client-urls http://10.0.1.10:2379 \
  --discovery http://localhost:8087/9b14ae6ce7764df5464542caface175d
  
$ etcd --name infra1 --initial-advertise-peer-urls http://10.0.1.11:2380 \
  --listen-peer-urls http://10.0.1.11:2380 \
  --listen-client-urls http://10.0.1.11:2379,http://127.0.0.1:2379 \
  --advertise-client-urls http://10.0.1.11:2379 \
  --discovery http://localhost:8087/9b14ae6ce7764df5464542caface175d
  
$ etcd --name infra2 --initial-advertise-peer-urls http://10.0.1.12:2380 \
  --listen-peer-urls http://10.0.1.12:2380 \
  --listen-client-urls http://10.0.1.12:2379,http://127.0.0.1:2379 \
  --advertise-client-urls http://10.0.1.12:2379 \
  --discovery http://localhost:8087/9b14ae6ce7764df5464542caface175d
```

这样一来，每个etcd进程启动的时候都把自己向discovery服务注册。当注册了
足够多的进程（上面例子里是3个）后，etcd机群就开始服务了。接下来也可以
有更多进程注册自己，但是不会是机群的正式成员，只是一reverse proxy的形
式工作。
