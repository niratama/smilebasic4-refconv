# プチコン4 リファレンスマニュアル変換ツール

## インストール

* perl 5.x と cpanm
    * 必要なCPANモジュールは後述の手順でインストールしておくこと
* MkDocs <https://www.mkdocs.org/>
* python 3.x
    * build後のドキュメントをローカルで見るのに使う
    * MkDocs が python 使っているので入っているはず

### CPANモジュールのインストール

```shell
cpanm --installdeps .
```

## マニュアルの変換と表示

```shell
perl convert.pl
mkdocs build
python3 -m http.server 8080 --directory site/
```

<http://0.0.0.0:8080/>にアクセスするとマニュアルが表示される
