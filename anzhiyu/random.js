var posts=["2025/01/07/搭建属于自己的发卡小店-独角数卡/","2025/01/07/hello-world/"];function toRandomPost(){
    pjax.loadUrl('/'+posts[Math.floor(Math.random() * posts.length)]);
  };