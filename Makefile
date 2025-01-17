PREFIX ?= /usr
DATADIR ?= $(PREFIX)/share
DESTDIR ?=


all: data/bigram.model \
	 data/bigram.model \
	 data/SKK-JISYO.akaza

# -------------------------------------------------------------------------

# wikipedia の前処理

work/jawiki/jawiki-latest-pages-articles.xml.bz2:
	mkdir -p work/jawiki/
	wget --no-verbose --no-clobber -O work/jawiki/jawiki-latest-pages-articles.xml.bz2 https://dumps.wikimedia.org/jawiki/latest/jawiki-latest-pages-articles.xml.bz2

work/jawiki/jawiki-latest-pages-articles.xml: work/jawiki/jawiki-latest-pages-articles.xml.bz2
	bunzip2 --keep work/jawiki/jawiki-latest-pages-articles.xml.bz2

work/jawiki/extracted/_SUCCESS: work/jawiki/jawiki-latest-pages-articles.xml
	python3 -m wikiextractor.WikiExtractor --quiet --processes 8 --out work/jawiki/extracted/ work/jawiki/jawiki-latest-pages-articles.xml
	touch work/jawiki/extracted/_SUCCESS

# -------------------------------------------------------------------------
#  Unidic の処理
# -------------------------------------------------------------------------

work/unidic/unidic.zip:
	mkdir -p work/unidic/
	wget --no-verbose --no-clobber -O work/unidic/unidic.zip https://clrd.ninjal.ac.jp/unidic_archive/csj/3.1.1/unidic-csj-3.1.1.zip

work/unidic/lex_3_1.csv: work/unidic/unidic.zip
	unzip -D -o -j work/unidic/unidic.zip -d work/unidic/
	touch work/unidic/lex_3_1.csv

# -------------------------------------------------------------------------

# Vibrato トーカナイズ

work/vibrato/ipadic-mecab-2_7_0.tar.gz:
	mkdir -p work/vibrato/
	wget --no-verbose --no-clobber -O work/vibrato/ipadic-mecab-2_7_0.tar.gz https://github.com/daac-tools/vibrato/releases/download/v0.3.1/ipadic-mecab-2_7_0.tar.gz

work/vibrato/ipadic-mecab-2_7_0/system.dic: work/vibrato/ipadic-mecab-2_7_0.tar.gz
	mkdir -p work/vibrato/
	tar -xmzf work/vibrato/ipadic-mecab-2_7_0.tar.gz -C work/vibrato/

work/jawiki/vibrato-ipadic/_SUCCESS: mecab-user-dict.csv work/jawiki/extracted/_SUCCESS work/vibrato/ipadic-mecab-2_7_0/system.dic
	akaza-data tokenize \
		--reader=jawiki \
		--user-dict=mecab-user-dict.csv \
		--system-dict=work/vibrato/ipadic-mecab-2_7_0/system.dic \
		work/jawiki/extracted \
		work/jawiki/vibrato-ipadic/ \
		-vvv

work/aozora_bunko/vibrato-ipadic/_SUCCESS: work/vibrato/ipadic-mecab-2_7_0/system.dic
	akaza-data tokenize \
		--reader=aozora_bunko \
		--user-dict=mecab-user-dict.csv \
		--system-dict=work/vibrato/ipadic-mecab-2_7_0/system.dic \
		aozorabunko_text/cards/ \
		work/aozora_bunko/vibrato-ipadic/ -vv

work/vibrato-ipadic.wfreq: work/jawiki/vibrato-ipadic/_SUCCESS work/aozora_bunko/vibrato-ipadic/_SUCCESS
	akaza-data wfreq \
		--src-dir=work/jawiki/vibrato-ipadic/ \
		--src-dir=work/aozora_bunko/vibrato-ipadic/ \
		--src-dir=corpus/ \
		work/vibrato-ipadic.wfreq -vvv

# threshold が 16 なのはヒューリスティックなパラメータ設定による。
# vocab ファイルを作る意味は、辞書の作成のためだけなので、わざわざ作らなくてもよいかもしれない。
work/vibrato-ipadic.vocab: work/vibrato-ipadic.wfreq
	akaza-data vocab --threshold 16 work/vibrato-ipadic.wfreq work/vibrato-ipadic.vocab -vvv


# -------------------------------------------------------------------------

# 統計的仮名かな漢字変換のためのモデル作成処理

work/stats-vibrato-unigram.wordcnt.trie: work/vibrato-ipadic.wfreq
	akaza-data wordcnt-unigram \
 		work/vibrato-ipadic.wfreq \
 		work/stats-vibrato-unigram.wordcnt.trie

work/stats-vibrato-bigram.wordcnt.trie: work/stats-vibrato-unigram.wordcnt.trie work/stats-vibrato-unigram.wordcnt.trie work/aozora_bunko/vibrato-ipadic/_SUCCESS
	mkdir -p work/dump/
	akaza-data wordcnt-bigram --threshold=3 \
		--corpus-dirs work/jawiki/vibrato-ipadic/ \
		--corpus-dirs work/aozora_bunko/vibrato-ipadic/ \
		work/stats-vibrato-unigram.wordcnt.trie work/stats-vibrato-bigram.wordcnt.trie

data/bigram.model: work/stats-vibrato-bigram.wordcnt.trie work/stats-vibrato-unigram.wordcnt.trie corpus/must.txt corpus/should.txt corpus/may.txt data/SKK-JISYO.akaza
	akaza-data learn-corpus \
		--delta=2000 \
		--may-epochs=10 \
		--should-epochs=100 \
		--must-epochs=10000 \
		corpus/may.txt \
		corpus/should.txt \
		corpus/must.txt \
		work/stats-vibrato-unigram.wordcnt.trie work/stats-vibrato-bigram.wordcnt.trie \
		data/unigram.model data/bigram.model \
		-v

data/unigram.model: data/bigram.model

# -------------------------------------------------------------------------

# システム辞書の構築。dict/SKK-JISYO.akaza、コーパスに書かれている語彙および work/vibrato-ipadic.vocab にある語彙。
# から、SKK-JISYO.L に含まれる語彙を除いたものが登録されている。

data/SKK-JISYO.akaza: work/vibrato-ipadic.vocab dict/SKK-JISYO.akaza  corpus/must.txt corpus/should.txt corpus/may.txt work/unidic/lex_3_1.csv
	akaza-data make-dict \
		--corpus corpus/must.txt \
		--corpus corpus/should.txt \
		--corpus corpus/may.txt \
		--unidic work/unidic/lex_3_1.csv \
		--vocab work/vibrato-ipadic.vocab \
		data/SKK-JISYO.akaza \
		-vvv

# -------------------------------------------------------------------------

evaluate: data/bigram.model
	akaza-data evaluate \
		 --corpus=anthy-corpus/corpus.0.txt \
		 --corpus=anthy-corpus/corpus.1.txt \
		 --corpus=anthy-corpus/corpus.2.txt \
		 --corpus=anthy-corpus/corpus.3.txt \
		 --corpus=anthy-corpus/corpus.4.txt \
		 --corpus=anthy-corpus/corpus.5.txt \
		 --eucjp-dict=skk-dev-dict/SKK-JISYO.L \
		 --utf8-dict=data/SKK-JISYO.akaza \
		 --model-dir=data/ \
		 -vv

# -------------------------------------------------------------------------

install:
	install -m 0755 -d $(DESTDIR)$(DATADIR)/akaza/model/default/
	install -m 0644 data/*.model $(DESTDIR)$(DATADIR)/akaza/model/default/
	install -m 0644 data/SKK-JISYO.* $(DESTDIR)$(DATADIR)/akaza/dict/

# -------------------------------------------------------------------------

test-data: work/vibrato/ipadic-mecab-2_7_0/system.dic

.PHONY: all install evaluate test-data

