<p align="center">
  <img height="200" title="Kubernetes Logo" src="images/k8s_logo_with_border.png">
</p>

Spin up a Kubernetes cluster for your CKA exam in minutes in AWS or GCP.

[Blog Entry on how to use this repository](https://mford.io/posts/easy-kubeadm-k8s-cluster/)

<!-- # Table Of Contents
- [Kubernetes Certification Motivation and Study Resources](readme/certification_and_study.md)
- [Building your Kubernetes Cluster for Studying](readme/building_the_cluster.md)
- [CKAD Exam Tips/Useful Kubernetes Links and Commands](readme/kubernetes_links.md) -->

Changes from geerling.kubernetes role (version 7.1.2):
- ./tasks/node-setup:
  - added task:
    - ```- shell: echo '1' > /proc/sys/net/ipv4/ip_forward```
- ./tasks/sysctl-setup.yml:
  - added task:
    - ```- name: Ensure br_netfilter is enabled.
            modprobe:
              name: br_netfilter
              state: present
            when: >
              ansible_distribution != 'Debian'
              or ansible_distribution_major_version | int < 10```
