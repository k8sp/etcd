VER="v2.3.6"

if [[ `uname` == "Darwin" ]]; then
    OS=darwin
elif [[ `uname` == "Linux" ]]; then
    OS=linux
fi

if [[ `uname -m` != "x86_64" ]]; then
    echo "This experiment requires a x86_64 computer".
    exit
else
    ARCH=amd64
fi

ETCD=etcd-$VER-$OS-$ARCH

if [[ ! -d $ETCD ]]; then
    if [[ ! -f $ETCD.zip ]]; then
	wget -c https://github.com/coreos/etcd/releases/download/$VER/$ETCD.zip -O $ETCD.zip
    fi 
    unzip $ETCD.zip
fi

(./$ETCD/etcd 2>&1 > ./single-node.log) &

./$ETCD/etcdctl set /hello Message
./$ETCD/etcdctl get /hello
