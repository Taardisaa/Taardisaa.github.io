---
layout: post
title: "Setting up a Windows VM for Reverse Engineering [Work in Progress]"
date: 2026-03-22 20:47 -0600
---

哥们正在高高兴兴的准备一堆用于进行逆向工程的工具，结果Windows Defender给我把这些玩意全都删了。甚至还警告说这些东西是"hack"；不是哥们，我要的可不就是hack吗！

因此我就想把Windows Defender给关了，但是最后感觉还是太不稳妥了。要是哥们真的不小心下了个神秘病毒把我的主环境干翻了，那可就不妙了。

因此我决定自己整一个Windows虚拟环境，里面放上各种工具什么的，这样就不会影响到host machine了。

## 准备VM和镜像

目前VMWare Workstation Pro已经对个人免费开放，只需要注册一下账号即可下载，这里就不赘述了：https://knowledge.broadcom.com/external/article/344595/downloading-and-installing-vmware-workst.html

然后准备win11镜像：https://www.microsoft.com/en-us/software-download/windows11

选择`Download Windows 11 Disk Image (ISO) for x64 devices`，然后我选择的语言版本是英语（美国），省事。

然后是Product key. 网上随便找了一下笑死：https://gist.github.com/rvrsh3ll/0810c6ed60e44cf7932e4fbae25880df

反正是虚拟机环境，whatever。

然后参考这篇文章来跳过登录微软账号：https://www.tomshardware.com/how-to/install-windows-11-without-microsoft-account

具体而言：Shift+F10打开命令行，输入`start ms-cxh:localonly`即可。旧版本可以尝试`OOBE\BYPASSNRO`。

接下来是安装VMware Tools. 安装完重启。

> VMWare Tools会使得host machine和guest machine之间的文件共享变得非常方便，但是也会带来一定安全隐患。若要进行真正的病毒测试，请确保虚拟机和主机之间没有共享文件夹，关闭VMware Tools的共享功能（或者不安装），并且在测试阶段关闭网络连接。

## 关闭Windows Defender

因此我参考一下教程把把Windows Defender的定期扫描给关了：https://www.bilibili.com/read/cv17691615

``pwsh
Set-MpPreference -ScanScheduleDay 8
Set-MpPreference -RemediationScheduleDay 8
Set-MpPreference -ScanOnlyIfIdleEnabled $False
```

