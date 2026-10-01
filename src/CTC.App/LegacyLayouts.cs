// SPDX-License-Identifier: MIT
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;

namespace CTC.App;
public static class LegacyLayouts
{
    // These resources are exact copies of the preserved 6.8.9 XAML.
    public static T Load<T>(string name) where T:class
    {
        using var stream=Application.GetResourceStream(new Uri("/ContextTokenCodex;component/Layouts/"+name+".xaml",UriKind.Relative))!.Stream;
        var item=(T)XamlReader.Load(stream);
        if(item is DependencyObject root)Apply(root);
        return item;
    }
    public static void Apply(DependencyObject root)
    {
        if(root is FrameworkElement element&&element is not TextBlock&&Application.Current.TryFindResource(element.GetType()) is Style style)element.Style=style;
        if(root is ScrollViewer scroll&&scroll.Tag?.ToString()!="CTC.PixelScroll")
        {
            scroll.Tag="CTC.PixelScroll";scroll.CanContentScroll=false;
            scroll.PreviewMouseWheel+=(_,e)=>
            {
                var source=e.OriginalSource as DependencyObject;
                while(source!=null&&source!=scroll){if(source is ComboBox box&&box.IsDropDownOpen||source is ScrollViewer)return;source=VisualTreeHelper.GetParent(source);}
                scroll.ScrollToVerticalOffset(Math.Clamp(scroll.VerticalOffset-Math.Clamp(24d*e.Delta/120,-96,96),0,scroll.ScrollableHeight));e.Handled=true;
            };
        }
        foreach(object child in LogicalTreeHelper.GetChildren(root))if(child is DependencyObject d)Apply(d);
    }
}
