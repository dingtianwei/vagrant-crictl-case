#!/bin/bash
set -eu

export DEBIAN_FRONTEND=noninteractive

default_k8s_major_version="1.26"
#default_sandbox_image_repository="registry.aliyuncs.com/google_containers"
#default_node_subnet="10.0.33"
#default_k8s_pod_network_cidr="10.244.0.0/16"
#default_k8s_service_cidr="10.96.0.0/12"
#default_node_role="worker"

k8s_major_version=${K8S_MAJOR_VERSION:-$default_k8s_major_version}
#sandbox_image_repository=${SANDBOX_IMAGE_REPOSITORY:-$default_sandbox_image_repository}
#node_subnet=${NODE_SUBNET:-$default_node_subnet}
#k8s_pod_network_cidr=${K8S_POD_NETWORK_CIDR:-$default_k8s_pod_network_cidr}
#k8s_service_cidr=${K8S_SERVICE_CIDR:-$default_k8s_service_cidr}
#node_role=${NODE_ROLE:-$default_node_role}

echo ">>> SHOW INFO"
echo "k8s_major_version: [${k8s_major_version}]"
#echo "sandbox_image_repository: [${sandbox_image_repository}]"
#echo "node_subnet: [${node_subnet}]"
#echo "node_ip: [$(sudo ip addr| grep "inet ${node_subnet}" | head -1 |  awk '{print $2}' | awk -F '/' '{print $1}')]"
#echo "k8s_pod_network_cidr: [${k8s_pod_network_cidr}]"
#echo "k8s_service_cidr: [${k8s_service_cidr}]"
#echo "node_role: [${node_role}]"
echo ">>>"


echo ">>> CONFIGURE IPV4 FORWARDING/ IPTABLES & BRIDGE TRAFFIC"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system > /dev/null 2>&1

echo ">>>"

echo ">>> CONFIG UBUNTU ALIYUN REPOSITORY"

code_name=$(. /etc/os-release && echo "$VERSION_CODENAME")
cat << EOF | sudo tee /etc/apt/sources.list.aliyun > /dev/null
deb https://mirrors.aliyun.com/ubuntu/ ${code_name} main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${code_name} main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${code_name}-security main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${code_name}-security main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${code_name}-updates main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${code_name}-updates main restricted universe multiverse

# deb https://mirrors.aliyun.com/ubuntu/ ${code_name}-proposed main restricted universe multiverse
# deb-src https://mirrors.aliyun.com/ubuntu/ ${code_name}-proposed main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${code_name}-backports main restricted universe multiverse
deb-src https://mirrors.aliyun.com/ubuntu/ ${code_name}-backports main restricted universe multiverse
EOF
if ! (diff /etc/apt/sources.list.aliyun /etc/apt/sources.list > /dev/null 2>&1) ; then
  sudo /usr/bin/cp -f /etc/apt/sources.list.aliyun /etc/apt/sources.list
  sudo apt-get update > /dev/null
fi
echo ">>>"

echo ">>> INSTALL CONTAINERD"
for pkg in docker.io docker-doc docker-compose containerd runc; do echo "uninstall $pkg"; sudo apt-get -y  --purge remove $pkg > /dev/null|| true; done
unset pkg
for pkg in  ca-certificates curl gnupg ; do echo "install $pkg"; sudo DEBIAN_FRONTEND=noninteractive  apt-get -y install $pkg ;done
unset pkg

curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn apt-key add -
echo \
  "deb [arch="$(dpkg --print-architecture)"] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update > /dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install containerd.io
sudo systemctl enable containerd
echo ">>>"


echo ">>> CONFIG CONTAINERD.IO"
PAUSE_IMAGE="registry.aliyuncs.com/google_containers/pause:3.5"
echo "PAUSE_IMAGE: [${PAUSE_IMAGE}]"
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo -E sed -i "s,sandbox_image = .*,sandbox_image = \"$PAUSE_IMAGE\",g" /etc/containerd/config.toml

sudo systemctl restart containerd
echo ">>>"

echo ">>> INSTALL CRI-TOOLS CNI"
if [ "$(echo -e "$k8s_major_version\n1.25" | sort -V | head -1)" = "1.25" ]; then
	sudo install -m 0755 -d /etc/apt/keyrings
	test -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg && sudo mv /etc/apt/keyrings/kubernetes-apt-keyring.gpg{,_$(date +%s)}
	curl -fsSL https://mirrors.aliyun.com/kubernetes-new/core/stable/v${k8s_major_version}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://mirrors.aliyun.com/kubernetes-new/core/stable/v${k8s_major_version}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
else
  curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn apt-key add -
  cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
fi
sudo apt-get update > /dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cri-tools  kubernetes-cni
echo ">>>"

echo ">>> CONFIG CRI-TOOLS"
cat << EOF | sudo tee /etc/crictl.yaml > /dev/null
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF
echo ">>>"

echo ">>> CONFIG CNI"

cat << EOF | sudo tee /etc/cni/net.d/10-local.conflist  > /dev/null
{
  "cniVersion": "0.3.1",
  "name": "eni0-bridge",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "eni0",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "ranges": [
          [
            {
              "gateway": "10.28.0.1",
              "subnet": "10.28.0.0/24"
            }
          ]
        ],
        "routes": [
          {
            "dst": "0.0.0.0/0"
          }
        ],
        "type": "host-local"
      }
    }
  ]
}

EOF

echo ">>>"

echo ">>> pod config"
cat << EOF | sudo tee /root/pod-config.json > /dev/null
{
  "metadata": {
    "name": "busybox-sandbox1",
    "namespace": "default",
    "attempt": 1,
    "uid": "fhcid83djaidwnduwk28bcsb"

  },
  "log_directory": "/tmp",
  "linux": {
  }
}
EOF
echo ">>>"

echo "Done"