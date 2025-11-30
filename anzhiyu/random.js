var posts=["2025/11/26/hello-world/","2025/11/26/pve9-upgrade-kit-1/","2025/11/26/pve9-upgrade-kit/"];function toRandomPost(){
    pjax.loadUrl('/'+posts[Math.floor(Math.random() * posts.length)]);
  };