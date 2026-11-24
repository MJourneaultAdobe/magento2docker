#!/usr/bin/env bash
set -e
trap 'exit 255' ERR

if [[ -f /run/m2d/auth.json ]]; then
    install -d -m 700 /root/.composer /home/magento/.composer
    install -m 600 /run/m2d/auth.json /root/.composer/auth.json
    install -m 600 -o magento -g magento /run/m2d/auth.json /home/magento/.composer/auth.json
    chown magento:magento /home/magento/.composer
fi
if [[ -f /run/m2d/gitconfig ]]; then
    install -m 600 /run/m2d/gitconfig /root/.gitconfig
    install -m 600 -o magento -g magento /run/m2d/gitconfig /home/magento/.gitconfig
fi
