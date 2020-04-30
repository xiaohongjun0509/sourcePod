#encoding:utf-8
require 'cocoapods'
require 'cocoapods-core'
require 'cocoapods/installer/analyzer.rb'
require 'xcodeproj'

# 不加下面两句，在添加文件到xcodeproj的时候会导致 invalid byte sequence in US-ASCII
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

module Pod
    @@dependencies = []

    @@cache_root = Config.instance.cache_root
    @@cache_podsFolder = @@cache_root + 'Pods' # 这个是cocoapod的cache目录
    @@sandbox_root = Config.instance.sandbox_root #/工程目录/Pods
    
    @@podrb_path = "你的podfile路径"
    @@sourceFile = "sourcePodList.rb" #需要看源码的库名单文件地址
    @@targetName = "targetName"
    @@workspacePath = "xxx.xcworkspace" #xcworkspace地址

    def Pod.readSourceFile(sourceFilePath = nil) #  读入需要引入源码的二进制库名单
        if sourceFilePath == nil || !File.exist?(sourceFilePath)
            puts "\033[33mWarning sourceFile not found\033[0m\n"
            return []
        end
        sourcePods = []
        File.open(sourceFilePath, "r") do |file|  
            file.each_line do |line| 
                sourcePods << line.strip
                # puts line                 
            end  
        end
        sourcePods
    end

    def Pod.pod_ek(name = nil, *requirements)
        params = requirements[0].clone
        if params[:bin] == true
            params.delete(:bin)
            params.delete(:subspecs)
            params.delete(:testspecs)
            params.delete(:appspecs)
            pod = { "name" => name, "params" => params }
            # puts pod
            @@dependencies << pod
        end
    end

    def Pod.readPodFile(file_path = nil, sourcePods = []) 
        if file_path == nil || !File.exist?(file_path)
            puts "\033[33mWarning podfile file not found\033[0m\n"
            return
        end
        File.open(file_path, "r") do |file|  
            file.each_line do |line| 
                if line.lstrip.start_with? "pod_ek"
                    eval(line, nil, file_path) # 你需要知道ruby每一行都可以看成一个函数调用
                    # puts line 
                end
            end  
        end
        dependencies = []
        @@dependencies.each do |dependency|
            # puts dependency["name"]
            if sourcePods.include?(dependency["name"])
                puts "found bin lib:#{dependency["name"]}"
                dependencies << dependency
            end
        end
        @@dependencies = dependencies
    end

    def Pod.downloadSource(dependencies = [])
        download_results = []
        dependencies.each do |dependency|
            download_request = Downloader::Request.new(:name => dependency["name"],
                :params => dependency["params"],
            )
            begin
                download_result = Downloader.download(download_request, nil, :can_cache => true) # 第二个参数传递一个文件夹路径的话，可以将库拷贝过去
                podPath = download_request.slug({})
                rr = @@cache_root + 'Pods' + podPath
                download_results << {"name" => dependency["name"], "podPath" => rr}
                # puts rr
            rescue Pod::DSLError => e
                raise Informative, "Failed to load '#{name}' podspec: #{e.message}"
            rescue => e
                raise Informative, "Failed to download '#{name}': #{e.message}"
            end
          end
        download_results
    end

    # def Pod.findSandBoxLibFolder(libName = nil)
    #     if libName == nil
    #         puts "\033[33mWarning libName is nil\033[0m\n"
    #         return ""
    #     end
    #     libFolderPath = @@sandbox_root + libName
    #     libFolderPath
    # end

    def Pod.findLib(libName = nil)
        if libName == nil
            puts "\033[33mWarning libName is nil\033[0m\n"
            return ""
        end
        libFolderPath = @@sandbox_root + libName
        libPath = ....# 自己拼接路径
        libPath
    end

    # 去找到二进制里面的目录
    def Pod.findLibSourcePath(libName = nil)
        if libName == nil
            puts "\033[33mWarning libName is nil\033[0m\n"
            return ""
        end
        libPath = Pod.findLib(libName) 
        if File.exist?(libPath)
            # 这里需要这个二进制库是在库名字的目录下build出来的，否则查找不正确
            path = `str=\`dwarfdump #{libPath} | grep 'DW_AT_decl_file' | grep #{libName} | head -n 1\`;str=${str#*\\"};echo ${str%%#{libName}*}#{libName}`
            return path.strip # 这里居然有个换行符！！！
        else
            puts "\033[33mWarning lib:#{libPath} is not found\033[0m\n"
            return nil
        end
    end

    def Pod.copyLibsToDest(download_results)
        #移动需要的pod到指定位置
        download_results.each do |result|
            # 去找到二进制里面的目录
            libDestPath = Pod.findLibSourcePath(result["name"])
            if libDestPath == nil 
                return
            end
            puts "find #{result["name"]} DestPath:#{libDestPath}"
            if !libDestPath.start_with?("/") && !libDestPath.start_with?("./")
                libDestPath = Dir.pwd + "/" + libDestPath
            end
            # 拷贝cache里面的库到指定位置
            result["libDestPath"] = libDestPath
            puts "copy lib to :#{libDestPath}"
            if File.exist?(libDestPath)
                FileUtils.chmod_R "u=wrx,go=rx", libDestPath  # 加回权限，否则删除不了
                FileUtils.rm_rf libDestPath
            elsif
                FileUtils.mkdir_p(File.dirname(libDestPath))
            end
            FileUtils.cp_r(result["podPath"], libDestPath)
        end
    end

    $codeExt = [".m", ".h", ".c", ".cpp", ".mm", ".pch"]
    $sourceExt = [".m", ".c", ".cpp", ".mm"]
    def Pod.addLib(lib_path, group)
        if File.directory? lib_path
            Dir.foreach(lib_path) do |file|
                Pod.addLibFiles(lib_path+"/"+file, group)
            end
        else 
        end
    end
    
    def Pod.addLibFiles(file_path, group, target)
        # puts "ff:#{file_path}"
        if File.directory? file_path
            # puts "AddGroup:#{file_path}"
            g=group.new_group(File.basename(file_path))
            Dir.foreach(file_path) do |file|
                if file !="." and file !=".."
                    addLibFiles(file_path+"/"+file, g, target)
                end
            end
            if g.empty?
                group.children.delete_at(group.children.index(g))
            else
                g.sort
            end
    
        else
            if $codeExt.include?(File.extname(file_path))
                # basename=File.basename(file_path)
                # puts basename
                # puts "AddFile:#{File.basename(file_path)}"
                file_ref = group.new_reference(file_path)
                if $sourceExt.include?(File.extname(file_path))
                    target.add_file_references([file_ref])
                end
                target.add_resources([file_ref])
                FileUtils.chmod "u=rx,go=rx", file_path
            end
        end
    end

    # 创建工程文件
    def Pod.createXcodeProj(targetName, download_results, workspacePath)
        projName = "SourcePod"
        projPath = "sourcePod/#{projName}.xcodeproj"
        puts "create #{projPath}"
        proj = Xcodeproj::Project.new(projPath)
        download_results.each do |result|
            target = proj.new_target(:static_library, result["name"], :ios, '9.0')
            Pod.addLibFiles(result["libDestPath"], proj.main_group, target)
        end
        proj.save()        
        # 添加到之前的workspace
        workspace = Xcodeproj::Workspace.new_from_xcworkspace(workspacePath) 
        root = workspace.document.root
        found = false
        root.children.each do |child|
            if child.is_a?(REXML::Element)
                location = child.attributes['location']
                if location.include?(projName)
                    # root.delete_element(child)
                    found = true
                    break
                end
            end
        end
        if !found 
            workspace << projPath
            workspace.save_as(workspacePath)
        end
    end

    def Pod.deleteSourceProj(workspacePath)
        puts "try remove sourcePod.proj"
        projName = "SourcePod"
        workspace = Xcodeproj::Workspace.new_from_xcworkspace(workspacePath) 
        root = workspace.document.root
        found = false
        root.children.each do |child|
            if child.is_a?(REXML::Element)
                location = child.attributes['location']
                if location.include?(projName)
                    root.delete_element(child)
                    found = true
                    puts "found and delete SourceProj"
                    break
                end
            end
        end
        if found 
            workspace.save_as(workspacePath)
        end
    end

    def Pod.sourceLook(sourceOpen, onlyInRuntime, targetName, workspacePath)
        # 创建工程文件, 并添加
        if !sourceOpen
            Pod.deleteSourceProj(workspacePath)
        else
            #下载需要的pod
            sourcePods = Pod.readSourceFile(@@sourceFile)
            if sourcePods.empty? 
                Pod.deleteSourceProj(workspacePath)
                return
            end
            Pod.readPodFile(@@podrb_path, sourcePods)
            download_results = Pod.downloadSource(@@dependencies) # [{"name"=>"PINCache", "podPath"=>"External/PINCache/26171f2f43ff1f67d79600e4dfd4d53e"}]
            #移动需要的pod到指定位置
            Pod.copyLibsToDest(download_results)
            if !onlyInRuntime
                Pod.createXcodeProj(targetName, download_results, workspacePath)
            else
                Pod.deleteSourceProj(workspacePath)
            end
        end
    end

    def Pod.sourceLookEvnMain
        puts " ***** Source Look Begin *******"
        isJenkis = ENV.fetch('IS_JENKINS', '0')
        puts "isJenkis=#{isJenkis}"
        if isJenkis == '0' # jenkin不需要这个功能
            sourceOpen = false
            onlyInRuntime = true
            sourcePodConfigPath = "sourcePodConfig.rb"
            if File.exist?(sourcePodConfigPath) 
                sourcePodConfig = eval(File.read(sourcePodConfigPath))
                sourceOpen = sourcePodConfig['sourceOpen'] if sourcePodConfig.key?('sourceOpen')
                onlyInRuntime = sourcePodConfig['onlyInRuntime'] if sourcePodConfig.key?('onlyInRuntime')
            else
                File.open(sourcePodConfigPath, "w") do |aFile|
                    aFile.puts("# SourceOpen是总开关; OnlyInRuntime为true的时候，不增加SourcePod工程，只拷贝代码到目录，运行时可以进入源码")
                    aFile.puts("{")
                    aFile.puts("'sourceOpen' => #{sourceOpen},")
                    aFile.puts("'onlyInRuntime' => #{onlyInRuntime},")
                    aFile.puts("}")
                end
            end
            puts "sourceOpen=#{sourceOpen}"
            puts "onlyInRuntime=#{onlyInRuntime}"
            Pod.sourceLook(sourceOpen, onlyInRuntime, @@targetName, @@workspacePath)
        end
        puts " ***** Source Look End *******"
    end
# puts Dir.pwd
# puts @@cache_podsFolder
# puts @@sandbox_root
# puts @@podrb_path 
# puts @@sourceFile 


# 程序开始
Pod.sourceLookEvnMain
        

  
end
