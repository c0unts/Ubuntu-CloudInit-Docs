#! /bin/bash

set -xe

VMID="${VMID:-8200}"
STORAGE="${STORAGE:-local-lvm}"

IMG="noble-server-cloudimg-amd64.img"
IMG_NOIMG="noble-server-cloudimg-amd64"
BASE_URL="https://cloud-images.ubuntu.com/noble/current"
EXPECTED_SHA=$(wget -qO- "$BASE_URL/SHA256SUMS" | awk '/'$IMG'/{print $1}')
NAME="ubuntu-noble-template"
SHORT_NAME="noble"

download() {
    wget -q "$BASE_URL/$IMG"
}

verify() {
    sha256sum "$IMG" | awk '{print $1}'
}

[ ! -f "$IMG" ] && download

ACTUAL_SHA=$(verify)

if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    rm -f "$IMG"
    download
    ACTUAL_SHA=$(verify)
    [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ] && exit 1
fi

rm -f $IMG_NOIMG-resized.img
cp $IMG $IMG_NOIMG-resized.img
qemu-img resize $IMG_NOIMG-resized.img 8G

qm destroy $VMID || true
qm create $VMID --name $NAME --ostype l26 \
    --memory 1024 --balloon 0 \
    --agent 1 \
    --bios ovmf --machine q35 --efidisk0 $STORAGE:0,pre-enrolled-keys=0 \
    --cpu host --socket 1 --cores 1 \
    --vga serial0 --serial0 socket  \
    --net0 virtio,bridge=vmbr0
qm importdisk $VMID $IMG_NOIMG-resized.img $STORAGE
qm set $VMID --scsihw virtio-scsi-pci --virtio0 $STORAGE:vm-$VMID-disk-1,discard=on
qm set $VMID --boot order=virtio0
qm set $VMID --scsi1 $STORAGE:cloudinit

cat << EOF | tee /var/lib/vz/snippets/ubuntu.yaml
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
# Taken from https://forum.proxmox.com/threads/combining-custom-cloud-init-with-auto-generated.59008/page-3#post-428772
EOF

qm set $VMID --cicustom "user=local:snippets/ubuntu.yaml"
qm set $VMID --tags ubuntu-template,$SHORT_NAME,cloudinit
qm set $VMID --ciuser $USER
qm set $VMID --sshkeys ~/lukas_public.pub
qm set $VMID --ipconfig0 ip=dhcp
qm template $VMID
