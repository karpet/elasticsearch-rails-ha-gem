require 'spec_helper'
require 'pp'

describe Elasticsearch::Rails::HA::IndexStager do
  before(:each) do
    ESHelper.delete_all_indices
  end

  after(:each) do
    ESHelper.delete_all_indices
  end

  it "generates index names" do
    stager = Elasticsearch::Rails::HA::IndexStager.new('Article')
    expect(stager.stage_index_name).to eq "articles_staged"
    expect(stager.tmp_index_name).to match(/^articles_\d{14}-\w{8}$/)
  end

  it "stages an index" do
    stager = stage_index
    aliases = ESHelper.client.indices.get_alias(index: stager.stage_index_name, name: '*')
    expect(aliases.keys.size).to eq 1
    expect(aliases.keys[0]).to eq stager.tmp_index_name
  end

  it "promotes a staged index to live" do
    stager = stage_index
    stager.promote
    Article.__elasticsearch__.refresh_index!

    response = Article.search('title:test')
    expect(response.results.size).to eq 2

    aliases = ESHelper.client.indices.get_alias(index: Article.index_name, name: '*')
    expect(aliases.keys[0]).to eq stager.tmp_index_name
  end

  it "handles first-time migration to staged paradigm" do
    live_indexer = Elasticsearch::Rails::HA::ParallelIndexer.new(
      klass: 'Article',
      idx_name: Article.index_name,
      nprocs: 1,
      batch_size: 5,
      force: true,
      verbose: !ENV['QUIET']
    )
    live_indexer.run

    stager = stage_index
    stager.promote
    Article.__elasticsearch__.refresh_index!

    aliases = ESHelper.client.indices.get_alias(index: Article.index_name, name: '*')
    expect(aliases.keys[0]).to eq stager.tmp_index_name
  end

  def stage_index
    stager = Elasticsearch::Rails::HA::IndexStager.new('Article')
    indexer = Elasticsearch::Rails::HA::ParallelIndexer.new(
      klass: stager.klass,
      idx_name: stager.tmp_index_name,
      nprocs: 1,
      batch_size: 5,
      force: true,
      verbose: !ENV['QUIET']
    )
    indexer.run
    stager.alias_stage_to_tmp_index
    stager
  end
end
