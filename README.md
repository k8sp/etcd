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

TODO(y): 如何让进程之间互相知道对方

TODO(y): 主进程的角色


