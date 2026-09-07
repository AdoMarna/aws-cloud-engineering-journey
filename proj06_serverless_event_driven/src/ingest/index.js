const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

const sqs = new SQSClient({});

const QUEUE_URL = process.env.QUEUE_URL;

exports.handler = async (event) => {
  try {
    if (!QUEUE_URL) {
      console.error("QUEUE_URL environment variable is missing");

      return {
        statusCode: 500,
        body: JSON.stringify({
          error: "Server configuration error",
        }),
      };
    }

    let body;

    try {
      body =
        typeof event.body === "string"
          ? JSON.parse(event.body)
          : event.body;
    } catch (error) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: "Invalid JSON payload",
        }),
      };
    }

    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: "Payload must be a JSON object",
        }),
      };
    }

    if (!Array.isArray(body.items) || body.items.length === 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: "Field 'items' must be a non-empty array",
        }),
      };
    }

    if (!body.customerId || typeof body.customerId !== "string") {
      return {
        statusCode: 400,
        body: JSON.stringify({
          error: "Field 'customerId' is required",
        }),
      };
    }

    const order = {
      ...body,
      orderId: body.orderId || crypto.randomUUID(),
      customerId: body.customerId,
      receivedAt: new Date().toISOString(),
    };

    await sqs.send(
      new SendMessageCommand({
        QueueUrl: QUEUE_URL,
        MessageBody: JSON.stringify(order),
      })
    );

    console.log("Order successfully queued", {
      orderId: order.orderId,
    });

    return {
      statusCode: 202,
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: "Order accepted",
        orderId: order.orderId,
      }),
    };
  } catch (error) {
    console.error("Failed to enqueue order", error);

    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        error: "Unable to process request",
      }),
    };
  }
};
