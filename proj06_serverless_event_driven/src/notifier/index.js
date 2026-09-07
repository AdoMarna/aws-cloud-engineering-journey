exports.handler = async (event) => {
  console.log(
    "Received EventBridge event:",
    JSON.stringify(event, null, 2)
  );

  const detail = event.detail || {};

  const orderId = detail.orderId;
  const customerId = detail.customerId;

  if (!orderId) {
    console.error("Missing orderId in EventBridge event");

    throw new Error("Invalid OrderProcessed event");
  }

  console.log("====================================");
  console.log("        ORDER NOTIFICATION");
  console.log("====================================");
  console.log(`Order ID    : ${orderId}`);
  console.log(`Customer ID : ${customerId || "unknown"}`);
  console.log(`Status      : ${detail.status || "PROCESSED"}`);
  console.log(`Processed   : ${detail.processedAt || "unknown"}`);
  console.log("Notification sent successfully");
  console.log("====================================");

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: "Notification processed",
      orderId,
    }),
  };
};
