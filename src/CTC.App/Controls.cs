// SPDX-License-Identifier: MIT
using System;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

namespace CTC.App;
public static class Controls
{
    public static SolidColorBrush Ink => Brush("#0D1B2A");
    public static SolidColorBrush Panel => Brush("#1B263B");
    public static SolidColorBrush Line => Brush("#415A77");
    public static SolidColorBrush Muted => Brush("#778DA9");
    public static SolidColorBrush Text => Brush("#E0E1DD");
    public static SolidColorBrush Brush(string hex)=>(SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
    public static TextBlock Label(string text,double size=12,bool muted=false)=>new(){Text=text,FontSize=size,Foreground=muted?Muted:Text,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,3,0,3)};
    public static Button Button(string text,Action click,string tip="",string id="")
    {
        var b=new Button{Content=text,Margin=new Thickness(0,0,5,4),Padding=new Thickness(8,5,8,5),ToolTip=tip.Length>0?tip:text};
        b.Click+=(_,_)=>click();AutomationProperties.SetName(b,tip.Length>0?tip:text);if(id.Length>0)AutomationProperties.SetAutomationId(b,id);return b;
    }
    public static Border Tile(UIElement body)=>new(){Background=Panel,CornerRadius=new CornerRadius(7),Padding=new Thickness(10),Margin=new Thickness(0,0,6,6),Child=body};
    public static Border Divider()=>new(){Height=1,Background=Line,Margin=new Thickness(0,10,0,10)};
    public static ScrollViewer Scroll(UIElement body)
    {
        var s=new ScrollViewer{Content=body,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,CanContentScroll=false};
        s.PreviewMouseWheel+=(_,e)=>
        {
            // Only handle the innermost scroll viewer. Use small fixed pixel steps.
            var source=e.OriginalSource as DependencyObject;
            while(source!=null&&source!=s){if(source is ScrollViewer)return;source=VisualTreeHelper.GetParent(source);}
            s.ScrollToVerticalOffset(s.VerticalOffset-Math.Sign(e.Delta)*24);e.Handled=true;
        };
        return s;
    }
    public static Expander Details(string name,UIElement body,bool open=false,string id="")
    {
        var e=new Expander{Header=name,Content=body,IsExpanded=open,Margin=new Thickness(0,3,0,3)};
        if(id.Length>0)AutomationProperties.SetAutomationId(e,id);return e;
    }
}
