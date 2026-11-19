export type OrderLineAmountInput = {
  quantity: number | string;
  rate: number | string;
  tax_rate: number | string;
  discount: number | string;
};

export type OrderTotals = {
  subtotal: number;
  taxTotal: number;
  discountTotal: number;
  grandTotal: number;
};

const roundMoney=(value:number)=>Math.round((value+Number.EPSILON)*100)/100;

export function calculateOrderTotals(lines: OrderLineAmountInput[]): OrderTotals {
  let subtotal=0;
  let taxTotal=0;
  let discountTotal=0;
  for(const line of lines){
    const quantity=Number(line.quantity)||0;
    const rate=Number(line.rate)||0;
    const taxRate=Number(line.tax_rate)||0;
    const discount=roundMoney(Number(line.discount)||0);
    const gross=roundMoney(quantity*rate);
    subtotal+=gross;
    discountTotal+=discount;
    taxTotal+=roundMoney(Math.max(0,gross-discount)*taxRate/100);
  }
  subtotal=roundMoney(subtotal);
  discountTotal=roundMoney(discountTotal);
  taxTotal=roundMoney(taxTotal);
  return {subtotal,taxTotal,discountTotal,grandTotal:roundMoney(subtotal+taxTotal-discountTotal)};
}
