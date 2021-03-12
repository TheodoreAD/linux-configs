# docker
# ======
# update your existing list of packages
sudo apt update
# add the GPG key for the official Docker repository to your system
curl -sS -Lf https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
# add the Docker repository to APT sources
# latest release doesn't work for 19.10 eoan, 19.04 disco works
# sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu disco stable"
# update the package database with the Docker packages from the newly added repo
sudo apt update
# make sure you are about to install from the Docker repo instead of the default Ubuntu repo
# check that docker-ce is not installed, but the candidate for installation is from the Docker repository for Ubuntu 19.10 (eoan)
apt-cache policy docker-ce
# install
sudo apt install -y docker-ce
# check that it’s running
sudo systemctl status docker
# on ERROR: Couldn't connect to Docker daemon at http+docker://localhost - is it running?
# if it is stopped and masked: Loaded: masked (Reason: Unit docker.service is masked.)
# then you need to unmask the service:
#sudo systemctl unmask docker
# on problems with the socket docker binds on you can allow your user to be owner of the socket:
#sudo chown $USER:docker /var/run/docker.sock
# run docker without sudo
# add the docker group if it doesn't already exist
sudo groupadd docker
# add docker group to the user
sudo gpasswd -a $USER docker
# alternative method, less safe since without -a it would remove the user from all other groups
# sudo usermod -aG docker $USER
# ? ACTION: Log out and login back again to refresh group membership.
# restart the docker daemon for the group changes to take effect
sudo service docker restart
# check you can run without sudo
docker run hello-world
# change daemon cgroup driver to systemd
sudo tee "/etc/docker/daemon.json" >/dev/null <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "dns": ["1.1.1.1", "1.0.0.1", "192.168.100.1"]
}
EOF
sudo mkdir -p /etc/systemd/system/docker.service.d
# restart docker
sudo systemctl daemon-reload
sudo systemctl restart docker
# check your storage driver is overlay2 and cgroup driver is systemd
docker info

# kind
# ====
#GO111MODULE="on" go get sigs.k8s.io/kind@v0.7.0

# kuberentes
# ==========
# disable swap
sudo swapoff -a
sudo systemctl enable docker
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
# xenial is the repo that receives updates
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt update
sudo apt-get install -y kubeadm kubectl kubelet
#
# # find root partition drive
# df / -BG
# sudo lshw -short -C disk
# # check if drive is individual or raid
# cat /proc/scsi/scsi
# # check if your drive is HDD (1) or SDD (0)
# # if physical
# cat /sys/block/sda/queue/rotational
# lsblk -o NAME,TYPE,FSTYPE,SIZE,VENDOR,REV,ROTA
# lsblk -St
# # if virtual
# cat /sys/block/vda/queue/rotational

# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
# verify connectivity to the gcr.io container image registry
sudo kubeadm config images pull
# start cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16
#  --control-plane-endpoint=DNS-name

# add config to user
mkdir -p "${HOME}/.kube"
sudo cp -i "/etc/kubernetes/admin.conf" "${HOME}/.kube/config"
sudo chown $(id -u):$(id -g) "${HOME}/.kube/config"
# install CNI plugin
kubectl apply -f "https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
# disable control plane taint to allow pod creation on control plane
sudo kubectl taint nodes --all node-role.kubernetes.io/master-
# join machine as worker node
#sudo kubeadm join 172.31.192.5:6443 \
#  --token k937r8.s6ilx972bxk4nwd7 \
#  --discovery-token-ca-cert-hash sha256:d643272866e4c8175f958cd44afb3629cdc7902eec0b95d250fd7c014e0f82f3

kubeadm token create --print-join-command

SYS_CONFIG_DIR="${HOME}/.kube/install/system"
md "${SYS_CONFIG_DIR}"

# # local volumes do not support dynamic provisioning
# # we need to wait until the feature is implemented
# # https://kubernetes.io/blog/2019/04/04/kubernetes-1.14-local-persistent-volumes-ga/
# # https://kubernetes.io/docs/concepts/storage/#local
# tee "${HOME}/.kube/storageclass-k8s-local.yaml" >/dev/null <<EOF
# apiVersion: storage.k8s.io/v1
# kind: StorageClass
# metadata:
#   name: local-storage
#   annotations:
#     storageclass.kubernetes.io/is-default-class: "true"
# provisioner: kubernetes.io/no-provisioner
# volumeBindingMode: WaitForFirstConsumer
# allowVolumeExpansion: true
# reclaimPolicy: Delete
# EOF

# https://github.com/openebs/openebs
# https://docs.openebs.io/docs/next/prerequisites.html#ubuntu
systemctl status iscsid
# if not installed:
# sudo apt-get install open-iscsi
# if not started:
sudo systemctl enable iscsid && sudo systemctl start iscsid
# deploy openebs in cluster
kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml
# https://docs.openebs.io/docs/next/localpv.html
# verify hostpath and device are added
kubectl get storageclass
# list items indentation was necesary, unlike in original instructions
tee "${SYS_CONFIG_DIR}/storageclass-openebs-local.yaml" >/dev/null <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-hostpath
  annotations:
    openebs.io/cas-type: local
    cas.openebs.io/config: |
      - name: StorageType
        value: "hostpath"
      - name: BasePath
        value: "/var/openebs/local/"
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: openebs.io/local
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
# load openebs local storageclass
kubectl apply -f "${SYS_CONFIG_DIR}/storageclass-openebs-local.yaml"
# verify hostpath is now default
kubectl get storageclass

# https://metallb.universe.tf/installation/
# install metallb
kubectl apply -f https://raw.githubusercontent.com/google/metallb/v0.9.3/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/google/metallb/v0.9.3/manifests/metallb.yaml
# On first install only
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
# configure metallb
CONFIGMAP_METALLB="${SYS_CONFIG_DIR}/configmap-metallb.yaml"
curl https://raw.githubusercontent.com/google/metallb/v0.9.3/manifests/example-layer2-config.yaml \
  -sL -o "${CONFIGMAP_METALLB}"
# replace default address space with the real one
sed -i 's|      - 192.*|      - 172.31.195.224/28|' "${CONFIGMAP_METALLB}"
kubectl apply -f "${CONFIGMAP_METALLB}"

# https://istio.io/docs/setup/getting-started/
# install istioctl system-wide in /opt with root ownership
curl -L https://istio.io/downloadIstio | sh -
ISTIO_DIR=$(echo istio-*)
find "${ISTIO_DIR}" -type d -exec chmod +x {} \;
sudo chown -R root:root "${ISTIO_DIR}"
sudo mv "${ISTIO_DIR}" "/opt"
sudo ln "/opt/${ISTIO_DIR}/bin/istioctl" "/usr/local/bin"
# install istio in k8s cluster
istioctl manifest apply \
  --set addonComponents.grafana.enabled=true \
  --set addonComponents.kiali.enabled=true \
  --set values.gateways.istio-ingressgateway.type=NodePort
# verify installation
istioctl manifest apply \
  --set addonComponents.grafana.enabled=true \
  --set addonComponents.kiali.enabled=true \
  --set values.gateways.istio-ingressgateway.type=NodePort \
  > "${SYS_CONFIG_DIR}/istio-generated-manifest.yaml"
istioctl verify-install -f "${SYS_CONFIG_DIR}/istio-generated-manifest.yaml"
# set utility env variables (current shell only)
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')

# enable NodePort if previously using LoadBalancer
istioctl upgrade --set values.gateways.istio-ingressgateway.type=NodePort


# helm
# ====
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add stable https://kubernetes-charts.storage.googleapis.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
