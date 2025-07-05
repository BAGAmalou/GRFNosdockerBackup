#!/bin/bash
# 检查whiptail是否安装
if ! command -v whiptail &> /dev/null; then
    echo "正在安装whiptail..."
    sudo apt-get update
    sudo apt-get install -y whiptail
fi

# 主备份函数
backup_images() {
    # ... [原有备份镜像代码保持不变] ...
}

# 主恢复函数（优化界面显示及增加分页功能，取消额外简化名称显示）
restore_images() {
    # ... [原有恢复镜像代码保持不变] ...
}

# 批量部署函数（优化界面显示）
deploy_images() {
    # ... [原有部署代码保持不变] ...
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
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 /vol2/1001/docker_backups/data 3>&1 1>&2 2>&3)
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
    backup_dir=$(whiptail --inputbox "请输入备份目录完整路径：" 10 60 /vol2/1001/docker_backups/data 3>&1 1>&2 2>&3)
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