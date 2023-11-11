<#
  .SYNOPSIS
  格式化输出为带 index 列的表格

  .DESCRIPTION
  实现：
  1) 先进行 Format-Table
  2) 然后从 Format-Table 中提取表格部分，并添加自增 index 列
#>
function Format-TableWithIndex
{
  [CmdletBinding()]
  [OutputType([string[]])]
  param(
    [Parameter(ValueFromPipeline)]
    [psobject[]]$Source=@()
  )

  begin
  {
    $data_lines = [System.Collections.ArrayList]::new()
  }
  process
  {
    $data_lines.AddRange($Source)
  }
  end
  {
    $data_lines_count = $data_lines.Count

    # 计算 $vid_col_width, $vid_col_name, $vid_col_format
    $vid_col_name = "#"
    $vid_col_width = [System.Math]::Max($vid_col_name.Length, "$data_lines_count".Length) + 1
    $vid_col_name =  $vid_col_name.PadLeft($vid_col_width,' ')
    $vid_col_format = "-" * $vid_col_width

    # 提取出有效表格部分，并添加上 vid 列，构成新表格
    $new_table = [System.Collections.ArrayList]::new(2 + $data_lines_count)
    $lines = ($data_lines | Format-Table -Wrap:$false | Out-String).Split("`n")
    $cur_line_number = -1
    $data_start_line_number = -1
    $data_end_line_number = -1
    $format_line_regex = [regex]::new("\s*\-+\s*")
    foreach ($l in $lines)
    {
      $cur_line_number++

      if($data_start_line_number -eq -1)
      {
        # 检测到格式行
        if($format_line_regex.IsMatch($l))
        {
          # 记录 data 起始,终止行号
          $data_start_line_number = $cur_line_number + 1
          $data_end_line_number = $data_start_line_number + $data_lines_count

          # header 行添加 vid 列表头, 并添加该行到 new_table
          $header_line = $lines[$cur_line_number-1]
          $$=$new_table.Add("$vid_col_name $header_line")

          # format 行添加到 new_table
          $$= $new_table.Add("$vid_col_format $l")
        }
      } else
      {
        if($cur_line_number -ge $data_end_line_number)
        {
          break
        }

        # data 行 vid 列添加自增值
        $vid_value = $cur_line_number - $data_start_line_number 
        #  1)
        # 10)
        $vid_col_data = "$vid_value".PadLeft($vid_col_width - 1, ' ') + ")"

        # data 行添加到 new_table
        $$=$new_table.Add("$vid_col_data $l")
      }     
    }
    return $new_table
  }
}

<#
  .SYNOPSIS
  Pick something from pipeline

  .EXAMPLE
  Get-Process | Pick -Title "Pick one you like"

  .EXAMPLE
  Get-Process | Pick -Multi -Gui -Title "Pick something you like"

  .EXAMPLE
  Get-Process | Pick -Multi -Title "Pick something you like"

  .EXAMPLE
  Get-Process | Pick -Multi -Fzf -Title "Pick something you like"

  .EXAMPLE
  Get-Process | Pick -Multi -Gum -Title "Pick something you like"
#>
function Pick
{
  [CmdletBinding(DefaultParameterSetName = "default")]
  param(
    # source from pipeline
    [Parameter(ValueFromPipeline)]
    [object[]]$Source=@(),

    # title
    [Parameter()]
    [Alias("t")]
    [string]$Title=" ",

    # multiple picking
    [Parameter()]
    [Alias("m")]
    [switch]$Multiple,

    # use Out-GridView gui
    [Parameter(ParameterSetName="default")]
    [switch]$Gui,

    # use gum tui
    [Parameter(ParameterSetName="gum")]
    [ValidateScript({Get-Command gum -ErrorAction Stop})]
    [switch]$Gum,
    
    # use fzf tui
    [Parameter(ParameterSetName="fzf")]
    [ValidateScript({Get-Command fzf -ErrorAction Stop})]
    [switch]$Fzf,
  
    # preview window (only for fzf)
    [Parameter(ParameterSetName="fzf")]
    [switch]$Preview
  )

  begin
  {
    $ErrorActionPreference="Stop"
    $list = [System.Collections.ArrayList]::new()
  }

  process
  {
    $list.AddRange($Source)
  }

  end
  {
    $gridview_outputmode = $Multiple ? "Multiple" : "Single"

    # 不能使用 $list，因为 process 中添加的 element 会自动转成 PSCustomObject
    # 故此处使用 $source 来判断入参类型
    # TODO 需要寻找更好的方法来区分类型
    $is_table_type = ($Source | Select-Object -First 1).GetType().Name -notin @("String","Double","Int32")

    # 截取 vid 正则
    $vid_regex = [regex]::new("\s*(\d+?)\)\s")

    switch ($PsCmdlet.ParameterSetName)
    {
      # Use `Out-GridView` or `Out-ConsoleGridView`
      'default'
      {
        if($Gui)
        {
          $list | Out-GridView -Title $Title -OutputMode $gridview_outputmode
        } else
        {
          $list | Out-ConsoleGridView -Title $Title -OutputMode $gridview_outputmode
        }
      }
      # Use `gum`
      'gum'
      {
        $limit_opts = $Multiple ? "--no-limit" : "--limit=1"

        if($is_table_type)
        {
          $list | Format-TableWithIndex
          #gum 不支持 table header 显示，故此处过滤
          | Select-Object -Skip 2 -First $list.Count
          | ForEach-Object { $_.Trim() }
          | gum filter --placeholder=" $Title" $limit_opts
          # gum 的结果进入 pipeline 后会莫名其妙增加
          # 第一行 failed xxx 和 多余空行, 此处将其过滤
          | Where-Object { $_ -notmatch "failed" -and $_ -notmatch "^\s*$"}
          | ForEach-Object {
            $index = $vid_regex.Match($_).Groups[1].Value
            $list[[int]$index]
          }
        } else
        {
          $list | gum filter --placeholder=" $Title" $limit_opts
          | Where-Object { $_ -notmatch "failed" }
        }
      }
      # Use `fzf`
      'fzf'
      {
        $header= if($Multiple)
        {
          "`e[1;5m$Title`e[m`n`n[ 选择/取消：<Tab> ]  [ 选择/取消所有：<Ctrl-z> ]  [ 确定：<Enter> ]  [ 退出：<Ctrl-c> ]`n`n"
        } else
        {
          "`e[1;5m$Title`e[m`n`n[ 确定：<Enter> ]  [ 退出：<Ctrl-c> ]`n`n"
        }

        $header_line = $is_table_type ? 2 : 0

        $limit_opts = $Multiple ? "--multi" : "--multi=0"

        $preview_window_opt = $Preview ? "--preview-window=right:50%" : "--preview-window=hidden"
      
        if($is_table_type)
        {
          $list | Format-TableWithIndex 
          | & "fzf" "$limit_opts" "$preview_window_opt" "--header=$header" "--header-lines=$header_line" "--layout=reverse" "--bind=ctrl-z:toggle-all"
          | ForEach-Object{
            $index = $vid_regex.Match($_).Groups[1].Value
            $list[[int]$index]
          }
        } else
        {
          $list
          | & "fzf" "$limit_opts" "$preview_window_opt" "--header=$header" "--header-lines=$header_line" "--layout=reverse" "--layout=reverse" "--bind=ctrl-z:toggle-all"
        }
      }
    }
  }
}


