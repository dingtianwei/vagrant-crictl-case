# vagrant-crictl-case

本环境中，使用crictl创建pod会出现以下情况
```
$ sudo crictl runp /root/pod-config.json 
E0511 02:08:20.553230    4019 remote_runtime.go:176] "RunPodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: expected cgroupsPath to be of format \"slice:prefix:name\" for systemd cgroups, got \"/k8s.io/368492d2e8d70cc1be67f43bc3a4d3f816d6a6857d9802e5e946460bbef8aace\" instead: unknown"
FATA[0003] run pod sandbox: rpc error: code = Unknown desc = failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: expected cgroupsPath to be of format "slice:prefix:name" for systemd cgroups, got "/k8s.io/368492d2e8d70cc1be67f43bc3a4d3f816d6a6857d9802e5e946460bbef8aace" instead: unknown 
```

**环境说明：**
* 按照kubernetes(kubelet)的实践要求配置
* 目前安装的套件仅包含学习和实践containerd使用


## 问题记录
Q1[已解决]：将containerd的配置项中`plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup=true`修改为`plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup=false`，就可以创建pod了。
* ~`kubelet`实践中，要求这个配置`SystemdCgroup=true`~
*  为什么`crictl`在这个配置`SystemdCgroup=true`无法创建pod ？
* 如何保持`SystemdCgroup=true`的情况下，使用 `crictl` 创建pod？
* ~对于`crictl`来说，containerd中的配置`SystemdCgroup=true` 和 `SystemdCgroup=false` 在过程中有什么区别？~

使用这个json，可以在containerd中的配置`SystemdCgroup=true` 和 `SystemdCgroup=false`  情况下创建pod了。
```json
{
  "metadata": {
    "name": "busybox-sandbox1",
    "namespace": "default",
    "attempt": 1,
    "uid": "fhcid83djaidwnduwk28bcsb"

  },
  "log_directory": "/tmp",
  "linux": {
    "cgroup_parent": "/kubepods.slice/kubepods-besteffort.slice"
  }
}
```
参考：https://github.com/zhaojizhuang/containerd-book/issues/1

个人总结的原因是这样（不严格，细节或某些描述不一定正确，只是整体上便于我理解）：

1. 使用systemd配置和管理的cgoups层级为slice:prefix:name。可用通过systemd-cgls 查看系统的cgroup直观观察。
2. 对于containerd 来说，它只负责通用的cgoups部分，不管是采用cgroupfs 还是采用systemd ，都是一样的。
3. 如果containerd中配置systemdGroup=true，containerd的通用的cgroup部分不能直接使用，还需要借助cri客户端告诉它更多的信息以符合systemd cgroups的配置标准。
4. crictl使用中的json文件的linux.cgroup_parent 字段，正是这个作用，用来指定cri配置容器时使用什么slice


Q2[已解决]: 在不断尝试的过程中发现，就目前环境的配置，将`/etc/cni/net.d/10-local.conflist`删除后，却创建了一个异常pod，不明原因
```
vagrant@ubuntu-focal:~$ sudo su -
root@ubuntu-focal:~# crictl pods
POD ID              CREATED             STATE               NAME                NAMESPACE           ATTEMPT             RUNTIME

root@ubuntu-focal:~# rm -f /etc/cni/net.d/10-local.conflist

root@ubuntu-focal:~# crictl runp pod-config.json 
E0511 03:06:52.975045    4208 remote_runtime.go:176] "RunPodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to setup network for sandbox \"cf50c759109cff9d77c47b56920c3a1948a1c2c0dfa9b5ed1ac02254daf28483\": cni plugin not initialized"
FATA[0000] run pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox "cf50c759109cff9d77c47b56920c3a1948a1c2c0dfa9b5ed1ac02254daf28483": cni plugin not initialized 
root@ubuntu-focal:~# crictl pods
POD ID              CREATED             STATE               NAME                NAMESPACE           ATTEMPT             RUNTIME
cf50c759109cf       269 years ago       NotReady            busybox-sandbox1    default             1                   (default)
root@ubuntu-focal:~# crictl rmp cf50c759109cf
E0511 03:08:20.504126    4299 remote_runtime.go:224] "RemovePodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to forcibly stop sandbox \"cf50c759109cff9d77c47b56920c3a1948a1c2c0dfa9b5ed1ac02254daf28483\": failed to destroy network for sandbox \"cf50c759109cff9d77c47b56920c3a1948a1c2c0dfa9b5ed1ac02254daf28483\": cni plugin not initialized" podSandboxID="cf50c759109cf"
removing the pod sandbox "cf50c759109cf": rpc error: code = Unknown desc = failed to forcibly stop sandbox "cf50c759109cff9d77c47b56920c3a1948a1c2c0dfa9b5ed1ac02254daf28483": failed to destroy network for sandbox "cf50c759109cff9d77c47b56920c3a1948a1c2c0dfa9b5ed1ac02254daf28483": cni plugin not initialized

```

crictl找不到cni的配置，pod创建进行到一半panic了，没能清理pod。
