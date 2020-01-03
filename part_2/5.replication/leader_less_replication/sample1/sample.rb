# 基本は本に書いてある通りの実装
# クライアント側で戻ってきた値のマージを行う。マージ戦略は和集合なのでuniq
# サーバー側の処理として、本では「バージョン番号を持つ全ての値を上書きできます」とある部分は削除する処理としている（上書きして残してもしょうがないので…。）

class Client
  attr_reader :server, :name
  attr_accessor :cart, :last_received_version

  # @server: リクエスト先サーバーインスタンス（Serverクラスのインスタンス）
  # @name: ロギング用のクライアント名
  # @cart: カート（に入っている商品配列）
  # @last_received_version: 最終受信バージョン番号
  def initialize(name:, server:)
    @server = server
    @name = name
    @cart = []
    @last_received_version = nil
  end

  # serverに商品追加のリクエストを送信し、レスポンスを元にカート内容（と最終受信バージョン番号）を更新する
  def add(product:)
    # ロギング
    status
    puts "Client #{name} - add product: #{product}"

    # 最終受信バージョン番号、現在のカート内容＋今回追加商品を使ってリクエストデータ作成、送信
    data = build_request_data(added_product: product)
    responce = server.req(data)

    # ロギング
    puts "Client #{name} - received responce: #{responce}"

    # 最終受信バージョン番号更新、カート内容更新
    self.last_received_version, products = responce
    merge_cart(products: products)

    # ロギング
    status
  end

  private

  # カートに入っている商品に今回追加商品を追加した商品配列と、最終受信バージョン番号セットにする
  def build_request_data(added_product:)
    products = cart.dup
    products << added_product
    { version: last_received_version, products: products }
  end

  # 受信した商品リストは、サーバー側が保持している「上書きされなかったバージョンの商品リスト」の配列になっている
  # 商品リストに含まれる商品の「和集合」を取ることで現在のカート内容とする
  #
  # FIXME: ただ和集合を取ると「すでにカートに存在する商品」をさらに追加しても個数を増やせない
  def merge_cart(products:)
    self.cart = products.flatten.uniq.sort
  end

  # ロギング
  def status
    puts "Client #{name} - cart: #{cart}"
    puts "Client #{name} - last received version: #{last_received_version}"
  end
end

class Server
  attr_accessor :versions, :current_version

  # @versions: バージョン番号＆商品リストのセットを保持している配列。DBのレコードに相当。
  # @current_version: バージョン番号（addの度にインクリメント）
  def initialize
    @versions = []
    @current_version = 0
  end

  # リクエストを受信して以下の処理を行う
  #   - 新規バージョンの挿入（バージョン番号のインクリメント含む）
  #   - 不要になったバージョンの削除
  #   - 現在バージョン番号と、保持している全バージョンの商品リストを返却
  def req(data)
    # ロギング
    status
    puts "Server - received add request, data: #{data}"

    products = data[:products]
    req_version = data[:version]
    insert_new_version(products: products)
    clear_old_versions(req_version: req_version)

    # ロギング
    status

    # レスポンス返却
    build_response
  end

  private

  # バージョン番号のインクリメント、新バージョンの挿入
  def insert_new_version(products:)
    self.current_version += 1
    versions << { version: self.current_version, products: products.sort }
  end

  # 不要となったバージョンの削除
  def clear_old_versions(req_version:)
    # リクエストにバージョン番号が無い＝そのクライアントからの初回リクエスト時は削除対象が無いので終了
    return unless req_version

    current_versions = versions.dup
    # バージョンが無い場合は削除対象が無いので終了
    return if current_versions.empty?

    # バージョン配列を先頭から見ていってバージョン番号がリクエストのバージョン番号以下のものは削除
    v = current_versions.first[:version]
    while v <= req_version
      current_versions.shift
      break if current_versions.empty?

      v = current_versions.first[:version]
    end

    self.versions = current_versions
  end

  # 残っているバージョン＝上書きされなかったバージョンの商品リストを配列にまとめて（配列の配列にして）バージョン番号とセットで返却
  def build_response
    products = versions.inject([]) { |arr, cur| arr << cur[:products] }
    [current_version, products]
  end

  # ロギング
  def status
    puts "Server - versions: #{versions}"
    puts "Server - current version: #{current_version}"
  end
end

PRODUCTS = %w[milk flour eggs bacon ham coffee].freeze

server = Server.new
clients = (1..3).map { |i| Client.new(name: "client_#{i}", server: server) }

10.times do
  # ランダムなクライアントからランダムな商品の追加リクエストを送信
  product = PRODUCTS.sample
  client = clients.sample
  client.add(product: product)
  puts '--- --- --- --- --- --- --- ---'
end
