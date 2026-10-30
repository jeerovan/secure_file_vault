# Flutter's installed Windows engine exposes MSAA; UIA is disabled in that
# engine build. Use the actual native accessibility actions, not Dart callbacks.
Add-Type -AssemblyName Accessibility
Add-Type -ReferencedAssemblies ([Accessibility.IAccessible].Assembly.Location) @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using Accessibility;
public class FiFeAccessibleNode {
 public string name; public int role,state,depth,left,top,width,height;
}
public class FiFeAccessibility {
 delegate bool EnumChild(IntPtr window,IntPtr state);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr window,EnumChild callback,IntPtr state);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window,StringBuilder name,int size);
 [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr window,uint id,ref Guid guid,[MarshalAs(UnmanagedType.Interface)] out IAccessible accessible);
 [DllImport("oleacc.dll")] static extern int AccessibleChildren(IAccessible accessible,int start,int count,[Out,MarshalAs(UnmanagedType.LPArray,ArraySubType=UnmanagedType.Struct,SizeParamIndex=2)] object[] children,out int obtained);
 static IAccessible Root(IntPtr window) {
  IntPtr child=IntPtr.Zero;
  EnumChildWindows(window,(candidate,state)=>{var name=new StringBuilder(256);GetClassName(candidate,name,256);if(name.ToString()=="FLUTTERVIEW") {child=candidate;return false;}return true;},IntPtr.Zero);
  if(child==IntPtr.Zero) throw new Exception("Flutter view unavailable");
  var guid=new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");IAccessible root;
  int status=AccessibleObjectFromWindow(child,0xFFFFFFFC,ref guid,out root);
  if(status<0 || root==null) throw new Exception("MSAA root unavailable");
  return root;
 }
 static void Visit(IAccessible parent,object child,int depth,List<FiFeAccessibleNode> nodes,string action,ref int invoked) {
  if(nodes.Count>600 || depth>30) return;
  string name="";int role=0,state=0,left=0,top=0,width=0,height=0;
  try {name=parent.get_accName(child)??"";role=Convert.ToInt32(parent.get_accRole(child));state=Convert.ToInt32(parent.get_accState(child));parent.accLocation(out left,out top,out width,out height,child);} catch(COMException) {return;}
  nodes.Add(new FiFeAccessibleNode{name=name,role=role,state=state,depth=depth,left=left,top=top,width=width,height=height});
  if(action!=null && name==action) {parent.accDoDefaultAction(child);invoked++;return;}
  if(!(child is int) || (int)child!=0) return;
  int count=parent.accChildCount;
  if(count<=0 || count>600) return;
  var children=new object[count];int obtained;
  if(AccessibleChildren(parent,0,count,children,out obtained)<0) return;
  for(int index=0;index<obtained;index++) {
   var nested=children[index] as IAccessible;
   if(nested!=null) Visit(nested,0,depth+1,nodes,action,ref invoked);
   else if(children[index] is int) Visit(parent,children[index],depth+1,nodes,action,ref invoked);
   if(invoked>0) return;
  }
 }
 public static FiFeAccessibleNode[] Dump(IntPtr window) {
  int invoked=0;var nodes=new List<FiFeAccessibleNode>();Visit(Root(window),0,0,nodes,null,ref invoked);return nodes.ToArray();
 }
 public static bool Act(IntPtr window,string name) {
  int invoked=0;var nodes=new List<FiFeAccessibleNode>();Visit(Root(window),0,0,nodes,name,ref invoked);return invoked==1;
 }
}
'@
