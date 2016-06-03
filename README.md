# `etcd`

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

etcd的Github页面的Releases列表里有
[安装介绍](https://github.com/coreos/etcd/releases)。也可以用这个
[脚本](./single-node.sh)。

## 单点部署

如果不考虑利用Raft协议实现不间断服务，最简单的etcd配置可以只有一个进程。
这个进程监听本机 2379 端口。我们可以用 curl 之类的标准工具和这个端口通
信——写入或者读取 key-value pairs。

## 多点部署

我们可以在多台机器上启动多个 etcd 进程，每个进程可以通过本地 2379 端口
和客户端程序通信，此外 etcd 进程之间通过 2380 端口互相通信和协调。如果
当前主进程（*master*）挂了，剩下的进程利用Raft协议推举一个新的主进程。

有两种多点部署的机制：static和runtime。

### Static `etcd` Cluster

如果我们假设etcd进程不会挂，那么static方式就够了。static方式下，为了让
多个etcd进程互相知道对方，我们给每个进程一个命令行参数
`--initial-cluster`，用来指定etcd cluster里所有的进程，比如：

```
infra0=http://10.0.1.10:2380,infra1=http://10.0.1.11:2380,infra2=http://10.0.1.12:2380
```

此外，还需要告诉每个etcd进程自己是其中哪一个，为此需要设置
`--initial-advertise-peer-urls`，比如：

```
--initial-advertise-peer-urls http://10.0.1.10:2380
```

关于static方式，请参见CoreOS公司的
[这篇文档](https://coreos.com/etcd/docs/latest/clustering.html#static)。
