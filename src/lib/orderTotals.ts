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

export function calculateOrderTotals(lines: OrderLineAmountInput[]): OrderTotals {
  let subtotal=0;
  let taxTotal=0;
  let discountTotal=0;
  for(const line of lines){
    const quantity=Number(line.quantity)||0;
    const rate=Number(line.rate)||0;
    const taxRate=Number(line.tax_rate)||0;
    const discount=Number(line.discount)||0;
    const gross=quantity*rate;
    subtotal+=gross;
    discountTotal+=discount;
    taxTotal+=Math.max(0,gross-discount)*taxRate/100;
  }
  return {subtotal,taxTotal,discountTotal,grandTotal:subtotal+taxTotal-discountTotal};
}
