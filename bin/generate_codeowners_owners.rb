#! /usr/bin/ruby
require "fileutils"

module GenerateCodeownersOwners
  module_function

  def main
    # CODEOWNERS ファイルの解析
    parsed_data, parse_errors = parse_file
    # コードオーナー毎のファイル定義が、CODEOWNERS ファイルに含まれていることの確認
    check_errors = check_exist_self(parsed_data)

    unless parse_errors.empty? && check_errors.empty?
      (parse_errors + check_errors).each { |e| puts "[ERROR] #{e}" }
      exit(1)
    end

    # コードオーナー毎のファイルの出力
    recreate_codeowners_owners(parsed_data)

    puts "codeowners_owners/ 配下のファイルの再生成が正常に終了しました"
  end

  def parse_file
    parsed_data = {
      owner_hash: {},
      path_hash: {},
    }
    errors = []
    File.open(File.expand_path("../CODEOWNERS", __dir__)) do |f|
      f.each_line.with_index(1) do |line, index|
        next if line.match?(/^\s*($|#)/) # 空行,コメント行は無視

        valid_lin_splite = line.gsub(/\s*#.*$/, "").split(/\s+/) # 末尾のコメントを削除して分割

        path = File.expand_path(valid_lin_splite[0], "/")[1..] # パスの正規化
        if path.include?("*")
          errors.push "CODEOWNERS ファイルのパスに、ワイルドカード(*) が含まれています。 (#{index}行目)"
          next
        end
        if (same_path = parsed_data[:path_hash][path])
          errors.push "CODEOWNERS ファイルのパスに、重複があります。 (#{same_path.index}行目, #{index}行目)"
          next
        end
        if (child_path = parsed_data[:path_hash].find { |_, v| v[:path].start_with?("#{path}/") }&.dig(1))
          errors.push "CODEOWNERS ファイルのパスに、親ディレクトリによる上書きの定義があります。 (#{child_path.index}行目, #{index}行目)"
          next
        end

        owners = valid_lin_splite[1..]
        unless owners.all? { |o| o.start_with?("@") }
          errors.push "CODEOWNERS ファイルのオーナーに、'@' で始まらないオーナーが指定されています。 (#{index}行目)"
          next
        end
        owners.sort!.map! { |o| o[1..] } # 先頭の "@" を除去

        value = {
          path: path,
          index: index,
          owners: owners,
          children: [],
        }

        split_path = path.split("/")
        (split_path.size - 1).downto(1) do |i| # 親ディレクトリを探索
          parent_path = split_path[0...i].join("/")
          if parsed_data[:path_hash][parent_path]
            parsed_data[:path_hash][parent_path][:children].push value
            break
          end
        end

        owners.each do |o|
          parsed_data[:owner_hash][o] ||= []
          parsed_data[:owner_hash][o].push value
        end

        parsed_data[:path_hash][path] = value
      end
    end
    parsed_data[:owner_hash].each_value { |vs| vs.sort_by! { |v| v[:path] } }
    return parsed_data, errors
  end

  def check_exist_self(parsed_data)
    errors = []
    parsed_data[:owner_hash].each do |owner, values|
      unless values.any? { |v| v[:path] == codeowners_owner_path(owner) && v[:owners].size == 1 }
        errors.push "CODEOWNERS ファイルに '#{codeowners_owner_path(owner)} @#{owner}' の設定が必要です。"
      end
    end
    return errors
  end

  def recreate_codeowners_owners(parsed_data)
    codeowners_owners_dir = File.expand_path("../codeowners_owners", __dir__)
    if Dir.exist?(codeowners_owners_dir)
      FileUtils.rm_rf(codeowners_owners_dir)
    end

    parsed_data[:owner_hash].each do |owner, values|
      expand_codeowners_owner_path = File.expand_path("../#{codeowners_owner_path(owner)}", __dir__)

      # team の場合 @org/team-name のように、ディレクトリ構造となるためディレクトリを作成する
      FileUtils.mkdir_p(File.dirname(expand_codeowners_owner_path))
      File.open(expand_codeowners_owner_path, "w") do |f|
        values.each do |v|
          # codeowners_owner/ 下は CODEOWNERS 側でのオーナーの設定を含めてチェックしているため、不要
          next if v[:path] == codeowners_owner_path(owner)

          owners_str = v[:owners].map { |o| "@#{o}" }.join(" ")
          f.puts "#{v[:path]} #{owners_str}"
        end
        ignore_values = values.flat_map { |v| v[:children].filter { |c| !c[:owners].include?(owner) } }
        ignore_values.each do |v|
          f.puts "!#{v[:path]}"
        end
      end
    end
  end

  def codeowners_owner_path(owner)
    "codeowners_owners/#{owner}.txt"
  end
end

GenerateCodeownersOwners.main if __FILE__ == $0
