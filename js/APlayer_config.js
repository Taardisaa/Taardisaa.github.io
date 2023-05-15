const ap = new APlayer({
    container: document.getElementById('aplayer'),
    fixed: true,
    autoplay: false,
    theme: '#b7daff',
    loop: 'all',
    order: 'list',
    preload: 'auto',
    volume: 0.5,
    lrcType: 3,
    mutex: true,
    listFolded: false,

    audio: [{
            name: '一直很安静',
            artist: '阿桑',
            lrc: '/music/lrc/一直很安静 - 阿桑.lrc',
            cover: 'https://p1.music.126.net/SpovasHBud2A1qXXADXsBg==/109951163167455610.jpg?param=300x300',
            url: 'http://q0fzyzixq.bkt.clouddn.com/audio/mp3/一直很安静 - 阿桑.mp3'
                  },
        {
            name: '亲爱的旅人啊（Cover：木村弓）',
            artist: '周深',
            lrc: '/music/lrc/亲爱的旅人啊（Cover：木村弓）-周深.lrc',
            cover: 'https://p1.music.126.net/1YrCPOBV314i-mTtlDg8mQ==/109951164148664637.jpg?param=300x300',
            url: 'http://q0fzyzixq.bkt.clouddn.com/audio/mp3/亲爱的旅人啊（Cover：木村弓） - 周深.mp3'
                  }
        ]
});
