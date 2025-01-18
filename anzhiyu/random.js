var posts=["2025/01/13/Proxmox上配置Ubuntu和Debian-LXC容器/","2025/01/07/Docker搭建自己的专属订阅链接转换服务/","2025/01/07/LskyPro图床/","2025/01/07/OpenWRT-PVE-LXC-CT容器下的安装/","2025/01/07/istoreos无线网卡驱动/","2025/01/07/开源销售系统opensourcepos/","2025/01/07/搭建属于自己的发卡小店-独角数卡/","2025/01/07/hello-world/"];function toRandomPost(){
    pjax.loadUrl('/'+posts[Math.floor(Math.random() * posts.length)]);
  };