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


