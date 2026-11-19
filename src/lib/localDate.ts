export function toLocalDateInput(date:Date=new Date()):string {
  const year=date.getFullYear();
  const month=String(date.getMonth()+1).padStart(2,"0");
  const day=String(date.getDate()).padStart(2,"0");
  return year+"-"+month+"-"+day;
}

export function toLocalMonthInput(date:Date=new Date()):string {
  return date.getFullYear()+"-"+String(date.getMonth()+1).padStart(2,"0");
}

export function toLocalMonthStart(date:Date=new Date()):string {
  return toLocalMonthInput(date)+"-01";
}

export function toLocalMonthEnd(date:Date=new Date()):string {
  return toLocalDateInput(new Date(date.getFullYear(),date.getMonth()+1,0));
}
