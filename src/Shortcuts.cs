using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Web.Script.Serialization;

public class ShortcutDefinition {
    public string id{get;set;} public string group{get;set;} public string title{get;set;}
    public string[] commands{get;set;} public string[] bindings{get;set;}
}
public static class DesktopShortcuts {
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    const string English="qwertyuiop[]asdfghjkl;'zxcvbnm,.`";
    const string Russian="йцукенгшщзхъфывапролджэячсмитьбюё";
    static readonly string[] Modifiers={"alt","control","shift","lalt","ralt","lctrl","rctrl","lshift","rshift","lwin","rwin"};
    static readonly string[] Special={"space","escape","back","tab","enter","left","right","up","down","num_lock","scroll_lock","caps_lock","page_up","page_down","insert","delete","end","home","print_screen","multiply","add","subtract","decimal","divide","volume_up","volume_down","volume_mute","media_next_track","media_prev_track","media_stop","media_play_pause","oem_semicolon","oem_question","oem_tilde","oem_open_brackets","oem_pipe","oem_close_brackets","oem_quotes","oem_8","oem_102","oem_plus","oem_comma","oem_minus","oem_period"};
    public static ShortcutDefinition[] Load(string path){return Json.Deserialize<ShortcutDefinition[]>(File.ReadAllText(path));}
    public static string Normalize(string binding){
        string text=(binding??"").Trim().ToLowerInvariant();
        var keys=new List<string>();
        foreach(string part in text.Split('+')){
            string key=part.Trim();
            if(key.Length==1){int index=Russian.IndexOf(key[0]);if(index>=0)key=English[index].ToString();}
            switch(key){case "ctrl":key="control";break;case "esc":key="escape";break;case "return":key="enter";break;case "backspace":key="back";break;case "←":key="left";break;case "→":key="right";break;case "↑":key="up";break;case "↓":key="down";break;case ";":key="oem_semicolon";break;case "=":key="oem_plus";break;case "-":key="oem_minus";break;case "/":key="oem_question";break;case ",":key="oem_comma";break;case ".":key="oem_period";break;case "[":key="oem_open_brackets";break;case "]":key="oem_close_brackets";break;case "'":key="oem_quotes";break;case "`":key="oem_tilde";break;}
            if(keys.Contains(key))throw new ArgumentException("Клавиша повторяется: "+binding);
            keys.Add(key);
        }
        var mods=Modifiers.Where(x=>keys.Contains(x)).ToArray();var main=keys.Where(x=>!Modifiers.Contains(x)).ToArray();
        if((keys.Contains("alt")&&(keys.Contains("lalt")||keys.Contains("ralt")))||(keys.Contains("control")&&(keys.Contains("lctrl")||keys.Contains("rctrl")))||(keys.Contains("shift")&&(keys.Contains("lshift")||keys.Contains("rshift"))))throw new ArgumentException("Не смешивай общий и левый/правый модификатор: "+binding);
        if(mods.Length==0||main.Length!=1||!(Regex.IsMatch(main[0],@"^(?:[a-z0-9]|f(?:[1-9]|1[0-9]|2[0-4])|numpad[0-9])$")||Special.Contains(main[0])))throw new ArgumentException("Неверное сочетание «"+binding+"». Пример: Alt+E или Alt+Ctrl+←.");
        return String.Join("+",mods.Concat(main));
    }
    public static string[] Parse(string text){return String.IsNullOrWhiteSpace(text)?new string[0]:text.Split(';').Select(Normalize).ToArray();}
    public static string Format(string binding){
        return String.Join("+",Normalize(binding).Split('+').Select(x=>x=="control"?"Ctrl":x=="left"?"←":x=="right"?"→":x=="up"?"↑":x=="down"?"↓":x=="escape"?"Esc":x=="oem_comma"?",":x=="oem_period"?".":x.Length==1?x.ToUpperInvariant():Char.ToUpperInvariant(x[0])+x.Substring(1)));
    }
    public static string[] Effective(ShortcutDefinition item,Dictionary<string,string[]> overrides){return overrides!=null&&overrides.ContainsKey(item.id)?overrides[item.id]??new string[0]:item.bindings;}
    static string[] Physical(string binding){
        var variants=new List<string>{""};
        foreach(string key in binding.Split('+')){string[] options=key=="alt"?new[]{"lalt","ralt"}:key=="control"?new[]{"lctrl","rctrl"}:key=="shift"?new[]{"lshift","rshift"}:new[]{key};variants=variants.SelectMany(x=>options.Select(k=>x+"+"+k)).ToList();}
        return variants.Select(x=>String.Join("+",x.Split('+').Where(k=>k.Length>0).OrderBy(k=>k,StringComparer.Ordinal))).ToArray();
    }
    public static Dictionary<string,string[]> Validate(ShortcutDefinition[] definitions,Dictionary<string,string[]> overrides){
        var result=new Dictionary<string,string[]>();var used=new Dictionary<string,string>();
        foreach(var item in definitions){
            string[] keys=Effective(item,overrides).Select(Normalize).ToArray();result[item.id]=keys;
            foreach(string key in keys)foreach(string physical in Physical(key)){string owner;if(used.TryGetValue(physical,out owner))throw new ArgumentException("Сочетание "+Format(key)+" повторяется: «"+owner+"» и «"+item.title+"». Измени одно из назначений.");used[physical]=item.title;}
        }
        return result;
    }
    static Dictionary<string,string[]> ReadOverrides(string text){return Json.Deserialize<Dictionary<string,string[]>>(text??"{}")??new Dictionary<string,string[]>();}
    static string Quote(string text){return "'"+text.Replace("'","''")+"'";}
    public static string Render(string path,string overrides){
        var definitions=Load(path);var effective=Validate(definitions,ReadOverrides(overrides));var output=new StringBuilder();
        foreach(var item in definitions){string[] keys=effective[item.id];if(keys.Length==0)continue;output.Append("  - commands: [").Append(String.Join(", ",item.commands.Select(Quote))).Append("]\n    bindings: [").Append(String.Join(", ",keys.Select(Quote))).Append("]\n");}
        return output.ToString();
    }
    public static string HelpRows(string path,string overrides){
        var definitions=Load(path);var effective=Validate(definitions,ReadOverrides(overrides));var output=new StringBuilder();
        foreach(var item in definitions)if(effective[item.id].Length>0)output.Append("<tr><td>").Append(System.Security.SecurityElement.Escape(String.Join(" · ",effective[item.id].Select(Format)))).Append("</td><td>").Append(System.Security.SecurityElement.Escape(item.title)).Append("</td></tr>\n");
        return output.ToString();
    }
}
