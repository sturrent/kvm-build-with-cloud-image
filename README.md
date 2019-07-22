# kvm-build-with-cloud-image
Simple bash script to build VMs from cloud images in a kvm host

```
# bash build-vms.sh -h
build-vm.sh, usage: /virt/build-vms.sh -n|--name <VM_NAME> [-c|--cores <CORES_#>] [-m|--memory <MEMORY_IN_MB>] [-s|--sshkey <PUBLIC_SSH_KEY_FILE>] [-i|--image <IMAGE_FILE>]


"-h|--help" help info
"-n|--name" vm name
"-c|--cores" number of cores
"-m|--memory" memory in MB
"-s|--sshkey" path to public ssh key
"-i|--image" path to cloud image to use (ubuntu or centos)

```