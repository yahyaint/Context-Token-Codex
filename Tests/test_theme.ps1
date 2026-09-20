# SPDX-License-Identifier: MIT
Add-Type -AssemblyName PresentationFramework
$root=Split-Path $PSScriptRoot -Parent
$w=New-Object Windows.Window; $w.Width=320; $w.Height=200; $w.Title='CTC dropdown test'; $w.Topmost=$true
$theme=New-Object Windows.ResourceDictionary; $theme.set_Source([Uri]::new((Join-Path $root 'Theme.xaml'))); $w.Resources.MergedDictionaries.Add($theme)
$c=New-Object Windows.Controls.ComboBox; $c.Margin=20; $c.VerticalAlignment='Top'; $c.ItemsSource=@([pscustomobject]@{Label='Global';Path='a'},[pscustomobject]@{Label='Project';Path='b'}); $c.DisplayMemberPath='Label'; $c.SelectedIndex=0; $w.Content=$c
$script:stage=0; $script:passed=$false
$t=New-Object Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromMilliseconds(400)
$t.Add_Tick({if($script:stage -eq 0){[void]$w.Activate(); [void]$c.Focus(); $c.IsDropDownOpen=$true; $script:stage=1} else {$script:passed=$c.IsDropDownOpen; $c.SelectedIndex=1; $script:passed=$script:passed -and $c.SelectedItem.Path -eq 'b'; $t.Stop(); $w.Close()}})
$w.Add_Loaded({$t.Start()}); [void]$w.ShowDialog(); if(-not $script:passed){throw 'Dropdown open/select failed'}; 'PASS: themed dropdown opens and selects scope.'
