#!/bin/bash
# 检查操作系统
OS="$(uname -s)"

# 检查whiptail是否安装
if ! command -v whiptail &> /dev/null;
then
    echo "正在安装whiptail..."
    if [ "$OS" = "Linux" ];
    then
        sudo apt-get update
        sudo apt-get install -y whiptail
    else
        whiptail --msgbox "在非Linux系统上无法自动安装whiptail，请手动安装。" 10 60
        exit 1
    fi
fi

# 配置默认路径
DEFAULT_BACKUP_DIR="$HOME/docker_backups"
DEFAULT_DEPLOY_DIR="$HOME/docker_data"

# 日志函数
log() {
    local log_dir="$1"
    local log_file="$2"
    local message="$3"
    mkdir -p "$log_dir"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_dir/$log_file"
}

# 主备份函数
backup_images() {
    # 获取所有Docker镜像
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
    if [ -z "$images" ];
    then
        whiptail --msgbox "未找到Docker镜像！" 10 30
        return 1
    fi
    # 选择备份目录
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 "$DEFAULT_BACKUP_DIR" 3>&1 1>&2 2>&3)
    if [ -z "$backup_dir" ];
    then
        whiptail --msgbox "必须指定备份目录！" 10 30
        return 1
    fi
    
    # 创建目录（如果不存在）
    mkdir -p "$backup_dir"
    log "$backup_dir" "backup.log" "开始备份镜像"
    
    # 进度条计数
    total=$(echo "$images" | wc -l)
    count=0
    # 逐个备份镜像
    for img in $images;
    do
        # 生成文件名
        filename=$(echo "$img" | sed 's/[^a-zA-Z0-9._-]/_/g').tar
        save_path="$backup_dir/$filename"
        
        # 更新进度
        ((count++))
        percentage=$((count*100/total))
        echo "XXX"
        echo "$percentage"
        echo "正在备份: $img → $filename ($count/$total)"
        echo "XXX"
        
        # 执行备份
        if docker save -o "$save_path" "$img" 2>&1 | tee -a "$backup_dir/backup.log";
        then
            log "$backup_dir" "backup.log" "成功备份: $img 到 $filename"
        else
            log "$backup_dir" "backup.log" "备份失败: $img"
        fi
        
    done | whiptail --gauge "备份Docker镜像中..." 10 60 0
    # 完成提示
    whiptail --msgbox "备份完成！
备份目录: $backup_dir
日志文件: $backup_dir/backup.log" 12 60
}

# 主恢复函数（优化界面显示及增加分页功能，取消额外简化名称显示）
restore_images() {
    # 选择备份目录
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 "$DEFAULT_BACKUP_DIR" 3>&1 1>&2 2>&3)
    log "$backup_dir" "restore.log" "开始恢复镜像"
    
    if [ -z "$backup_dir" ]; then
        whiptail --msgbox "必须指定备份目录！" 10 30
        return 1
    fi
    
    if [ ! -d "$backup_dir" ]; then
        whiptail --msgbox "备份目录不存在！" 10 30
        return 1
    fi
    # 获取所有.tar备份文件，只保留文件完整路径作为选项显示
    backup_files=()
    while IFS= read -r -d $'\0' file; do
        backup_files+=("$file" "" OFF)
    done < <(find "$backup_dir" -maxdepth 1 -type f -name "*.tar" -print0)
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        whiptail --msgbox "未找到备份文件！" 10 30
        return 1
    fi
    
    # 分页选择逻辑（每页显示15个选项）
    selected_files=()
    page_size=15
    total_pages=$(((${#backup_files[@]} + page_size*3 - 1) / (page_size*3)))  # 计算总页数
    current_page=1
    
    while true; do
        # 计算当前页显示的选项范围
        start_idx=$(( (current_page - 1) * page_size ))
        end_idx=$(( start_idx + page_size - 1 < ${#backup_files[@]} ? start_idx + page_size - 1 : ${#backup_files[@]} - 1 ))
        page_opts=("${backup_files[@]:start_idx:$((end_idx - start_idx + 1))}")
        
        # 添加分页导航按钮
        nav_buttons=()
        if [ $current_page -gt 1 ]; then
            nav_buttons+=("prev" "上一页" OFF)
        fi
        if [ $current_page -lt $total_pages ]; then
            nav_buttons+=("next" "下一页" OFF)
        fi
        nav_buttons+=("confirm" "确认选择" OFF)
        
        # 合并选项和导航按钮
        display_opts=("${page_opts[@]}" "${nav_buttons[@]}")
        
        # 显示分页选择界面（高度35，宽度80，每页显示15个选项）
        choices=$(whiptail --title "选择要恢复的镜像（第$current_page/$total_pages页）" --checklist \
            "使用空格键选择/取消选择镜像，按<OK>确认" 35 80 15 \
            "${display_opts[@]}" \
            3>&1 1>&2 2>&3)
        
        if [ -z "$choices" ]; then
            whiptail --msgbox "未选择任何操作！" 10 30
            return 1
        fi
        
        # 处理分页导航
        if echo "$choices" | grep -q "prev"; then
            ((current_page--))
            continue
        fi
        if echo "$choices" | grep -q "next"; then
            ((current_page++))
            continue
        fi
        if echo "$choices" | grep -q "confirm"; then
            # 提取选中的文件路径（过滤掉导航按钮）
            selected_files=$(echo "$choices" | grep -v "prev\|next\|confirm")
            break
        fi
    done
    
    if [ -z "$selected_files" ]; then
        whiptail --msgbox "未选择任何镜像！" 10 30
        return 1
    fi
    # 处理选中的文件
    count=0
    total=$(echo "$selected_files" | wc -w)
    
    # 创建临时目录用于进度显示
    tmpfile=$(mktemp)
    
    (
        for file in $selected_files; do
            # 移除引号
            clean_file=$(echo "$file" | tr -d '"')
            filename=$(basename "$clean_file")
            
            # 更新进度
            ((count++))
            percentage=$((count*100/total))
            echo "XXX"
            echo "$percentage"
            echo "正在恢复: $filename ($count/$total)"
            echo "XXX"
            
            # 执行恢复
            docker load -i "$clean_file" 2>&1 | tee -a "$backup_dir/restore.log"
            sleep 1
        done
    ) | whiptail --gauge "恢复Docker镜像中..." 10 60 0
    
    # 完成提示
    whiptail --msgbox "恢复完成！\n已恢复 $count 个镜像\n日志文件: $backup_dir/restore.log" 12 60
}

# 批量部署函数（优化界面显示）
deploy_images() {
    # 获取所有Docker镜像
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
    if [ -z "$images" ]; then
        whiptail --msgbox "未找到Docker镜像！" 10 30
        return 1
    fi
    
    # 优化镜像名称显示（去除仓库地址和标签）
    image_list=()
    for img in $images; do
        # 简化镜像名称：去除仓库地址（如docker.io/）和标签（:latest）
        short_img=$(echo "$img" | sed 's|^[^/]*[/]*||; s|:latest||')
        image_list+=("$img" "$short_img" OFF)
    done
    
    # 让用户选择要部署的镜像（高度25，宽度80，每页显示12个选项）
    selected_images=$(whiptail --title "选择要部署的镜像" --checklist \
        "使用空格键选择/取消选择镜像（格式：真实名称 [显示名称]）" 25 80 12 \
        "${image_list[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$selected_images" ]; then
        whiptail --msgbox "未选择任何镜像！" 10 30
        return 1
    fi
    # 选择部署目录
    deploy_dir=$(whiptail --inputbox "请输入部署目录完整路径：" 10 60 "$DEFAULT_DEPLOY_DIR" 3>&1 1>&2 2>&3)
    log "$deploy_dir" "deploy.log" "开始部署容器"
    if [ -z "$deploy_dir" ]; then
        whiptail --msgbox "必须指定部署目录！" 10 30
        return 1
    fi
    
    # 创建部署目录
    mkdir -p "$deploy_dir"
    
    # 输入部署参数
    deploy_params=$(whiptail --inputbox "输入部署参数（可选）：\n例如：-p 8080:80 --name my-container" \
        12 60 3>&1 1>&2 2>&3)
    
    # 处理选中的镜像
    count=0
    total=$(echo "$selected_images" | wc -w)
    
    # 创建临时文件用于进度显示
    tmpfile=$(mktemp)
    
    (
        for img in $selected_images; do
            # 移除引号
            clean_img=$(echo "$img" | tr -d '"')
            
            # 为每个容器创建专用目录
            container_dir=$(echo "$clean_img" | sed 's/[^a-zA-Z0-9._-]/_/g')
            full_deploy_dir="$deploy_dir/$container_dir"
            mkdir -p "$full_deploy_dir"
            
            # 更新进度
            ((count++))
            percentage=$((count*100/total))
            echo "XXX"
            echo "$percentage"
            echo "正在部署: $clean_img ($count/$total)"
            echo "部署目录: $full_deploy_dir"
            echo "XXX"
            
            # 执行部署（包含自定义目录）
            docker run -d \
                -v "$full_deploy_dir:/app/data" \
                $deploy_params \
                $clean_img 2>&1 | tee -a "$deploy_dir/deploy.log"
                
            sleep 1
        done
    ) | whiptail --gauge "部署Docker容器中..." 10 60 0
    
    # 完成提示
    whiptail --msgbox "部署完成！\n已部署 $count 个容器\n部署目录: $deploy_dir\n日志文件: $deploy_dir/deploy.log" 12 60
}

# 备份容器数据函数
backup_container_data() {
    # 选择要备份的容器
    containers=$(docker ps -a --format "{{.ID}}:{{.Names}}")
    if [ -z "$containers" ]; then
        whiptail --msgbox "未找到Docker容器！" 10 30
        return 1
    fi
    
    # 转换为whiptail选项格式
    container_options=()
    while IFS=':' read -r id name; do
        container_options+=("$id" "$name" OFF)
    done <<< "$containers"
    
    # 让用户选择容器
    selected_containers=$(whiptail --title "选择要备份的容器" --checklist \
        "使用空格键选择/取消选择容器" 20 60 10 \
        "${container_options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$selected_containers" ]; then
        whiptail --msgbox "未选择任何容器！" 10 30
        return 1
    fi
    
    # 选择备份目录
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 "$DEFAULT_BACKUP_DIR/data" 3>&1 1>&2 2>&3)
    log "$backup_dir" "backup_data.log" "开始备份容器数据"
    if [ -z "$backup_dir" ]; then
        whiptail --msgbox "必须指定备份目录！" 10 30
        return 1
    fi
    
    # 创建目录（如果不存在）
    mkdir -p "$backup_dir"
    
    # 进度条计数
    total=$(echo "$selected_containers" | wc -w)
    count=0
    
    # 逐个备份容器数据
    ( 
        for container in $selected_containers; do
            # 移除引号
            clean_container=$(echo "$container" | tr -d '"')
            
            # 获取容器名称
            container_name=$(docker inspect --format '{{.Name}}' "$clean_container" | sed 's|/||')
            
            # 更新进度
            ((count++))
            percentage=$((count*100/total))
            echo "XXX"
            echo "$percentage"
            echo "正在备份容器数据: $container_name ($count/$total)"
            echo "XXX"
            
            # 创建容器备份目录
            container_backup_dir="$backup_dir/$container_name"
            mkdir -p "$container_backup_dir"
            
            # 获取容器挂载点
            mounts=$(docker inspect -f '{{range .Mounts}}{{if .Source}}{{.Source}}:{{.Destination}} {{end}}{{end}}' "$clean_container")
            
            if [ -z "$mounts" ]; then
                echo "容器 $container_name 没有数据卷" >> "$backup_dir/backup_data.log"
                sleep 1
                continue
            fi
            
            # 备份每个挂载点
            for mount in $mounts; do
                src=$(echo "$mount" | cut -d':' -f1)
                dest=$(echo "$mount" | cut -d':' -f2)
                
                # 生成备份文件名
                filename=$(echo "$dest" | sed 's|/|_|g').tar.gz
                
                # 执行备份
                echo "备份: $src -> $container_backup_dir/$filename" >> "$backup_dir/backup_data.log"
                tar -czf "$container_backup_dir/$filename" -C "$src" . 2>> "$backup_dir/backup_data.log"
            done
            
            sleep 1
        done
    ) | whiptail --gauge "备份容器数据中..." 10 60 0
    
    # 完成提示
    whiptail --msgbox "容器数据备份完成！\n备份目录: $backup_dir\n日志文件: $backup_dir/backup_data.log" 12 60
}

# 恢复容器数据函数
restore_container_data() {
    # 选择备份目录
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 "$DEFAULT_BACKUP_DIR/data" 3>&1 1>&2 2>&3)
    log "$backup_dir" "restore_data.log" "开始恢复容器数据"
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        whiptail --msgbox "备份目录不存在！" 10 30
        return 1
    fi
    
    # 获取容器备份列表
    container_backups=()
    while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            container_name=$(basename "$dir")
            container_backups+=("$container_name" "" OFF)
        fi
    done < <(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d)
    
    if [ ${#container_backups[@]} -eq 0 ]; then
        whiptail --msgbox "未找到容器备份！" 10 30
        return 1
    fi
    
    # 选择要恢复的容器备份
    selected_backups=$(whiptail --title "选择要恢复的容器数据" --checklist \
        "使用空格键选择/取消选择容器备份" 20 60 10 \
        "${container_backups[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$selected_backups" ]; then
        whiptail --msgbox "未选择任何容器备份！" 10 30
        return 1
    fi
    
    # 进度条计数
    total=$(echo "$selected_backups" | wc -w)
    count=0
    
    # 逐个恢复容器数据
    (
        for backup in $selected_backups; do
            # 移除引号
            clean_backup=$(echo "$backup" | tr -d '"')
            
            # 更新进度
            ((count++))
            percentage=$((count*100/total))
            echo "XXX"
            echo "$percentage"
            echo "正在恢复容器数据: $clean_backup ($count/$total)"
            echo "XXX"
            
            # 恢复每个备份文件
            backup_path="$backup_dir/$clean_backup"
            for file in "$backup_path"/*.tar.gz; do
                if [ ! -f "$file" ]; then
                    continue
                fi
                
                # 从文件名解析目标路径
                dest_path=$(basename "$file" | sed 's/.tar.gz$//' | sed 's/_/\//g')
                
                # 创建目标目录
                mkdir -p "$dest_path"
                
                # 执行恢复
                echo "恢复: $file -> $dest_path" >> "$backup_dir/restore_data.log"
                tar -xzf "$file" -C "$dest_path" 2>> "$backup_dir/restore_data.log"
            done
            
            sleep 1
        done
    ) | whiptail --gauge "恢复容器数据中..." 10 60 0
    
    # 完成提示
    whiptail --msgbox "容器数据恢复完成！\n已恢复 $count 个容器数据\n日志文件: $backup_dir/restore_data.log" 12 60
}

# 主菜单
main_menu() {
    while true; do
        choice=$(whiptail --menu "Docker镜像管理" 18 60 6 \
            "1" "备份镜像" \
            "2" "恢复镜像" \
            "3" "批量部署（含自定义目录）" \
            "4" "备份容器数据" \
            "5" "恢复容器数据" \
            "6" "退出" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1) backup_images ;;
            2) restore_images ;;
            3) deploy_images ;;
            4) backup_container_data ;;
            5) restore_container_data ;;
            6) break ;;
            *) whiptail --msgbox "无效选择！" 10 30 ;;
        esac
    done
}

# 检查Docker是否可用
if ! command -v docker &> /dev/null; then
    whiptail --msgbox "Docker未安装！请先安装Docker。" 10 50
    exit 1
fi

# 执行主菜单
main_menu