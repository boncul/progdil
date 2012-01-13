
require 'pathname'     #pathname modülünü çağır
require 'pythonconfig' #pythonconfig modülünü çağır
require 'yaml'         #yaml modülünü çağır

CONFIG = Config.fetch('presentation', {})

PRESENTATION_DIR = CONFIG.fetch('directory', 'p')                          #ilkinde ara, yoksa ikinciyi al
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg') #ilkinde ara, yoksa ikinciyi al
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')                     #PRESENTATION_DIR ile index.html'yi birleştir
IMAGE_GEOMETRY = [ 733, 550 ]
DEPEND_KEYS    = %w(source css js)
DEPEND_ALWAYS  = %w(media)
TASKS = {                              #TASKS'ın kapsamı içinde bir nevi komut tanımı (ör. ":index" sunumları indeksler)
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

presentation   = {} #içi boş "key => value" değişkeni
tag            = {} #içi boş "key => value" değişkeni

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd) #statik sınıf değişkeni (ör. Pathname: home/burak)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s #tam yolu göreli yola çevir, string yap
  end
  def self.to_filelist(path) #dosya yolunu kontrol et, '*' ile split et, liste yap
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string) #png fotoğrafları commentle
  require 'chunky_png'        #chunky_png modülünü çağır
  require 'oily_png'          #oily_png modülünü çağır

  image = ChunkyPNG::Image.from_file(file) #metadata erişimi
  image.metadata['Comment'] = 'raked'      #raked commentini yaz
  image.save(file)                         #kaydet
end

def png_optim(file, threshold=40000)        #png fotoğrafları optimize et
  return if File.new(file).size < threshold #dosyanın boyutu treshold'dan küçük mü?
  sh "pngnq -f -e .png-nq #{file}"          #shell komutlarını kullanarak optimize et
  out = "#{file}-nq"
  if File.exist?(out)                                       #out var mı?
    $?.success? ? File.rename(out, file) : File.delete(out) #başarılı mı?, varsa yeniden isimlendir, eskisini sil
  end
  png_comment(file, 'raked')
end

def jpg_optim(file)                     #jpg fotoğrafları optimize et
  sh "jpegoptim -q -m80 #{file}"        #shell komutlarını kullanarak optimize et
  sh "mogrify -comment 'raked' #{file}" #shell komutlarını kullanarak fotoğrafı comment açıkla
end

def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"] #png'leri pngs, jpg'leri jpgs listelerinde topla

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }     #resimleri çıkış formatına göre al
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i]                         #boyut belirlenenden büyük mü?
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s #büyükse boyutlandır
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) } #png'leri png_optim ile optimize et
  jpgs.each { |f| jpg_optim(f) } #jpg'leri jpg_optim ile optimize et

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|                    #markdown dosyalarını oluştur
      sh "grep -q '(.*#{name})' #{src} && touch #{src}" #(shell komutlarını kullanarak, sessizce ( -q), ekrana basmadan)
    end
  end
end

default_conffile = File.expand_path(DEFAULT_CONFFILE) #yolu DEFAULT_CONFFILE'daki yola dönüştür

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir| #PRESENTATION_DIR ile '_.' ile başlayanları birleştir
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide']                           #landslide değişkenine 'landslide' config dosyasını ata
    if ! landslide                                            #landslide değilse
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış" #stderr'i puts ile ekrana bas
      exit 1                                                  #hata çıkışı
    end

    if landslide['destination']                                                         #landslide 'destinstion ise
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin" #stderr'i ekrana bas
      exit 1                                                                            #hata çıkışı
    end

    if File.exists?('index.md') #'index.md' var ise
      base = 'index'            #dosyanın adı base'in içinde
      ispublic = true           #public yap
    elsif File.exists?('presentation.md') #'presentation.md' var ise
      base = 'presentation'               #dosyanın adı base'in içinde
      ispublic = false                    #public yapma
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı" #bu ikisi dışında verilmişse stderr'i ekrana bas
      exit 1                                                                        #hata çıkışı
    end

    basename = base + '.html'                   #<dosya adı> + <.html> uzantısı (base'i html yap)
    thumbnail = File.to_herepath(base + '.png') #küçük resim oluştur (to_herepath ile base'de verilen dosyada)
    target = File.to_herepath(basename)

    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end

    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)    #target'ı temizle
    deps.delete(thumbnail) #thumbnail'ı temizle

    tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

presentation.each do |k, v|
  v[:tags].each do |t| #etiketleme
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten] #TASKS'ı kullanarak görev tablosu

presentation.each do |presentation, data|    #sunumda dolaş
  ns = namespace presentation do             #isim uzayı oluştur
    file data[:target] => data[:deps] do |t| #':target' ve ':deps' i al
      chdir presentation do
        sh "landslide -i #{data[:conffile]}" #shell ile 'landslide -i' komutuyla sunumu başlat
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        unless data[:basename] == 'presentation.html' #'presentation' u 'presentation.html' yap
          mv 'presentation.html', data[:basename]
        end
      end
    end

    file data[:thumbnail] => data[:target] do #küçük resmi hedefe getir
      next unless data[:public]
      sh "cutycapt " +                        #resmi düzenle
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " + #en az 1024'e
          "--min-height=768 " + #768 olsun
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}" #yeniden boyutlandır
      png_optim(data[:thumbnail])                  #png'yi optimize et
    end

    task :optim do
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail] #küçük resmi indexle

    task :build => [:optim, data[:target], :index] #':optim', ':target' ve ':index'i build et

    task :view do #task'ı ':view' ile görüntüle
      if File.exists?(data[:target])                                    #hedef dosya var mı?
        sh "touch #{data[:directory]}; #{browse_command data[:target]}" #varsa shell komutlarından 'touch' ile dokun
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"      #yoksa stderr'i ekrana bas
      end
    end

    task :run => [:build, :view] #sunumu başlat

    task :clean do          #temizle, kimi?:
      rm_f data[:target]    #hedef dosyayı ve
      rm_f data[:thumbnail] #küçük resmi
    end

    task :default => :build #öntanımlı görev => inşa et
  end

  ns.tasks.map(&:to_s).each do |t| #ns'in görevlerini al, map işlevine sok
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name] #eğer tasktab[name] yoksa devam et(döngüden çık)
    tasktab[name][:tasks] << t
  end
end

namespace :p do
  tasktab.each do |name, info| #görev tablosu yardımıyla teni görevleri tanımla
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do
    index = YAML.load_file(INDEX_FILE) || {} #INDEX_FILE'ı yükle
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort #sunumu seç
    unless index and presentations == index['presentations'] #eşitse
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f| #INDEX_FILE'ı yazılabilir olarak aç
        f.write(index.to_yaml)          #index'i 'to_yaml'a tabi tut, sonra yaz
        f.write("---\n")                #"---\n" yaz
      end
    end
  end

  desc "sunum menüsü"
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v| #k ve v'ye göre sırala
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu| #sunum seç
      menu.default = "1"    #varsayılan sunum '1'
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke #rakefile
  end
  task :m => :menu
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
