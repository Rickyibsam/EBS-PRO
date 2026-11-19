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
    const quantity=Number(line.quantity);
    const rate=Number(line.rate);
    const taxRate=Number(line.tax_rate);
    const discount=Number(line.discount);
    if(![quantity,rate,taxRate,discount].every(Number.isFinite)||quantity<0||rate<0||taxRate<0||discount<0){
      throw new Error("Order quantity, rate, tax and discount must be valid non-negative values.");
    }
    const gross=quantity*rate;
    if(discount>gross+0.000001)throw new Error("A line discount cannot exceed the pre-tax gross amount.");
    subtotal+=gross;
    discountTotal+=discount;
    taxTotal+=Math.max(0,gross-discount)*taxRate/100;
  }
  return {subtotal,taxTotal,discountTotal,grandTotal:subtotal+taxTotal-discountTotal};
}
