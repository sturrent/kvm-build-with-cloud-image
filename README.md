# kvm-build-with-cloud-image
Simple bash script to build VMs from cloud images in a kvm host

You have to install the following tools before you can use it:
```
sudo apt update; sudo apt install qemu qemu-kvm libvirt-bin  bridge-utils  virt-manager -y
```

Usage:
```
sudo bash build-vms.sh -h
build-vm.sh, usage: bash build-vms.sh -n|--name <VM_NAME> [-c|--cores <CORES_#>] [-m|--memory <MEMORY_IN_MB>] [-s|--sshkey <PUBLIC_SSH_KEY_FILE>] [-i|--image <IMAGE_FILE>] [-d|--delete]

"-h|--help" help info
"-n|--name" vm name
"-c|--cores" number of cores
"-m|--memory" memory in MB
"-s|--sshkey" path to public ssh key
"-i|--image" path to cloud image to use (ubuntu or centos)
"-d|--delete" delete VM

```
