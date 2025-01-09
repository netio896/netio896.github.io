var posts=["2025/01/07/Docker搭建自己的专属订阅链接转换服务/","2025/01/07/OpenWRT-PVE-LXC-CT容器下的安装/","2025/01/07/搭建属于自己的发卡小店-独角数卡/","2025/01/07/hello-world/"];function toRandomPost(){
    pjax.loadUrl('/'+posts[Math.floor(Math.random() * posts.length)]);
  };