# type Title = { platform: string; title: string; url: string; };
# type Detail = { player: string; };
# type TitleDetail = {
#   platform: string;
#   title: string;
#   url: string;
#   genre: string;
#   player: string;
# };

cheerio = require 'cheerio'
fetch = require 'node-fetch'
fs = require 'fs'
{ parseString } = require 'xml2js'

# fetchTitleList: () => Promise<string>
fetchTitleList = () ->
  # FIXME: time=
  url = 'https://www.nintendo.co.jp/data/software/xml/wiiu_vc.xml?time=48730027'
  fetch(url)
    .then (response) ->
      if response.status < 200 or 299 < response.status
        throw new Error('status : ' + response.status)
      response.text()

# fetchAndSaveTitleListCache: () => Promise<string>
fetchAndSaveTitleListCache = () ->
  fetchTitleList()
    .then (text) ->
      fs.writeFileSync('./cache/wiiu_vc.xml', text)
      text

# loadTitleListCache: () => string
loadTitleListCache = () ->
  try
    fs.readFileSync('./cache/wiiu_vc.xml', { encoding: 'utf-8' })
  catch
    null

# parseXml: (xmlString: string) => Promise<Xml>
parseXml = (xmlString) ->
  new Promise (resolve, reject) ->
    parseString xmlString, (error, result) ->
      if error? then reject(error) else resolve(result)

# idToPlatform: (platformId: string) => string
idToPlatform = (platformId) ->
  return 'FC ' if platformId is '26'
  return 'SFC' if platformId is '27'
  return 'GBA' if platformId is '28'
  return 'PCE' if platformId is '31'
  return 'MSX' if platformId is '32'
  return 'DS ' if platformId is '35'
  return 'N64' if platformId is '36'
  return platformId

# parseTitleList: (xml: Xml) => Title[]
parseTitleList = (xml) ->
  # TitleInfoList:
  #   TitleInfo: [
  #     {
  #       InitialCode: [ 'WUPFAJJ' ]
  #       TitleName: [ 'バルーンファイト' ]
  #       Kana: [ 'バルーンファイト' ]
  #       MakerName: [ '任天堂' ]
  #       MakerKana: [ '' ]
  #       Price: [ '514円(税込)' ]
  #       SalesDate: [ '2013.4.27' ]
  #       SoftType: [ 'vc' ]
  #       PlatformID: [ '26' ]
  #       DlIconFlg: [ '1' ]
  #       LinkURL: [ '/titles/20010000000564' ]
  #       ScreenshotImgFlg: [ '1' ]
  #       ScreenshotImgURL: [ 'https://img-eshop.cdn.nintendo.net/i/91a29316a41a61f21bd57a9b5d8540fc67777f10de74f7368128a24021b2547d.jpg' ]
  #     }
  #   ]
  xml.TitleInfoList.TitleInfo.map (i) ->
    {
      platform: idToPlatform(i.PlatformID[0])
      title: i.TitleName[0]
      url: 'https://www.nintendo.co.jp' + i.LinkURL[0]
    }

# fetchOrLoadTitleList: () => Promise<Title[]>
fetchOrLoadTitleList = () ->
  Promise
    .resolve loadTitleListCache()
    .then (xml) ->
      if xml?
        Promise.resolve(xml)
      else
        fetchAndSaveTitleListCache()
    .then parseXml
    .then parseTitleList

# fetchTitleDetail: (url: string) => Promise<string>
fetchTitleDetail = (url) ->
  fetch(url)
    .then (response) ->
      if response.status < 200 or 299 < response.status
        throw new Error('status : ' + response.status)
      response.text()

# urlToCacheId: (url: string) => string
urlToCacheId = (url) ->
  match = url.match(/[^\/]+$/)
  unless match?
    throw new Error('url : ' + url)
  id = match[0]

# fetchAndSaveTitleDetailCache: (url: string) => Promise<string>
fetchAndSaveTitleDetailCache = (url) ->
  id = urlToCacheId url
  fetchTitleDetail(url)
    .then (text) ->
      fs.writeFileSync('./cache/wiiu_vc_' + id + '.html', text)
      text

# loadTitleDetailCache: (url: string) => string
loadTitleDetailCache = (url) ->
  try
    id = urlToCacheId url
    fs.readFileSync('./cache/wiiu_vc_' + id + '.html', { encoding: 'utf-8' })
  catch
    null

# parseTitleDetail = (htmlString: string) => Detail
parseTitleDetail = (htmlString) ->
  $ = cheerio.load htmlString
  genre = $('.basic-info dl').eq(0).find('dd').text().trim()
  player = $('.basic-info dl').eq(1).find('dd').text().trim()
  { genre, player }

# fetchOrLoadTitleDetail = (title: Title) => Promise<TitleDetail>
fetchOrLoadTitleDetail = (title) ->
  Promise
    .resolve loadTitleDetailCache(title.url)
    .then (htmlString) ->
      if htmlString?
        Promise.resolve(htmlString)
      else
        fetchAndSaveTitleDetailCache(title.url)
          .then (result) ->
            sleep = 1000
            new Promise (resolve) ->
              setTimeout((() -> resolve(result)), sleep)
    .then parseTitleDetail
    .then (detail) ->
      Object.assign({}, title, detail)

# ...
fetch = () ->
  fetchOrLoadTitleList()
    .then (titleList) ->
      titleList.reduce (promise, title) ->
        promise
          .then (result) ->
            console.log 'fetch : ' + title.title + ' ' + title.url
            fetchOrLoadTitleDetail title
              .then (titleDetail) ->
                result.concat([titleDetail])
      , Promise.resolve([])
    .then (detail) ->
      fs.writeFileSync('./cache/title_detail_list.json', JSON.stringify(detail))
      console.log detail
    , (error) ->
      console.error error

# ...
list = () ->
  filePath = './cache/title_detail_list.json'
  json = JSON.parse(fs.readFileSync(filePath, { encoding: 'utf-8' }))
  player = json.filter((i) -> i.player isnt '1人')
  genreMap = player.reduce((genreMap, i) ->
    genreMap[i.genre] ?= []
    genreMap[i.genre].push(i)
    genreMap
  , {})
  genres = Object.keys(genreMap).map (genre) ->
    list = genreMap[genre]
    result = list
      .filter (i) ->
        return false if i.platform is 'FC '
        return true if i.platform is 'SFC'
        return true if i.platform is 'GBA'
        return false if i.platform is 'PCE'
        return false if i.platform is 'MSX'
        return true if i.platform is 'DS '
        return true if i.platform is 'N64'
        return false
      .map (i) -> '    ' + i.platform + ' ' + i.title + ' ' + i.url
    { genre, result }
  genres
    .filter(({ result }) -> result.length > 0)
    .forEach ({ genre, result }) ->
      console.log　genre
      result
        .forEach (i) -> console.log i

main = () ->
  command = process.argv[2]
  fetch() if command is 'fetch'
  list() if command is 'list'

main()
