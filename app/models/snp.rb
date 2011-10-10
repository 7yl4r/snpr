class Snp < ActiveRecord::Base
  has_many :user_snps, foreign_key: :snp_name, primary_key: :name
  has_many :plos_paper
  has_many :mendeley_paper
  has_many :snpedia_paper
  has_many :snp_comments
  serialize :allele_frequency
  serialize :genotype_frequency

  validates_uniqueness_of :name

  searchable do
    text :name
  end

  after_create :default_frequencies

  def default_frequencies
    # if variations is empty, put in our default array
    self.allele_frequency ||= { "A" => 0, "T" => 0, "G" => 0, "C" => 0}
    self.genotype_frequency ||= {}
  end

  def self.update_papers
    max_age = 31.days.ago

    snps = Snp.select([ :id, :mendeley_updated, :snpedia_updated, :plos_updated ]).
      where([ 'mendeley_updated < ? or snpedia_updated < ? or plos_updated < ?',
              max_age, max_age, max_age ]).find_each do |snp|
      Resque.enqueue(Mendeley, snp.id) if snp.mendeley_updated < max_age
      Resque.enqueue(Snpedia,  snp.id) if snp.snpedia_updated  < max_age
      Resque.enqueue(Plos,     snp.id) if snp.plos_updated     < max_age
    end
  end
  
  def self.update_frequencies
    Snp.find_each do |s|
      s.allele_frequency ||= { "A" => 0, "T" => 0, "G" => 0, "C" => 0}
      s.genotype_frequency ||= {}
      UserSnp.where(:snp_name => s.name).find_each do |us|
        if s.allele_frequency.has_key?(us.local_genotype[0].chr)
          s.allele_frequency[us.local_genotype[0].chr] += 1
        else
          s.allele_frequency[us.local_genotype[0].chr] = 1
        end

        if us.local_genotype.length > 1
          if s.allele_frequency.has_key?(us.local_genotype[1].chr)
            s.allele_frequency[us.local_genotype[1].chr] +=  1
          else
            s.allele_frequency[us.local_genotype[1].chr] = 1
          end
        end

        if s.genotype_frequency.has_key?(us.local_genotype.rstrip)
          s.genotype_frequency[us.local_genotype.rstrip] +=  1
          
        elsif us.local_genotype.length > 1
          if s.genotype_frequency.has_key?(us.local_genotype[1].chr+us.local_genotype[0].chr)
            s.genotype_frequency[us.local_genotype[1].chr+us.local_genotype[0].chr] +=  1
          else
            s.genotype_frequency[us.local_genotype.rstrip] = 1
          end
        else
          s.genotype_frequency[us.local_genotype.rstrip] = 1
        end
      end
      s.save
    end
  end
end
