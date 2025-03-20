#!/bin/bash
#
containerd config default > config.toml
sudo cp config.toml /etc/containerd/config.toml
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
