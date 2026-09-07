const {
  DynamoDBClient,
  PutItemCommand,
} = require("@aws-sdk/client-dynamodb");

const {
  EventBridgeClient,
  PutEventsCommand,
} = require("@aws-sdk/client-eventbridge");

const dynamodb = new DynamoDBClient({});
const eventBridge = new EventBridgeClient({});

const TABLE_NAME = process.env.TABLE_NAME;
const EVENT_BUS_NAME = process.env.EVENT_BUS_NAME;

exports.handler = async (event) => {
  if (!TABLE_NAME || !EVENT_BUS_NAME) {
    throw new Error(
      "Missing TABLE_NAME or EVENT_BUS_NAME environment variable"
    );
  }

  console.log(`Processing ${event.Records?.length || 0} SQS messages`);

  for (const record of event.Records || []) {
    try {
      await processRecord(record);
    } catch (error) {
      console.error("Failed to process SQS message", {
        messageId: record.messageId,
        error: error.message,
      });
      throw error;
    }
  }

  console.log("SQS batch processed successfully");
};

async function processRecord(record) {
  let order;

  try {
    order = JSON.parse(record.body);
  } catch (error) {
    throw new Error(
      `Invalid JSON in SQS message ${record.messageId}`
    );
  }

  validateOrder(order);

  const now = new Date().toISOString();

  const item = {
    PK: {
      S: `ORDER#${order.orderId}`,
    },

    SK: {
      S: `ORDER#${order.orderId}`,
    },

    orderId: {
      S: String(order.orderId),
    },

    customerId: {
      S: String(order.customerId),
    },

    items: {
      S: JSON.stringify(order.items),
    },

    status: {
      S: "PROCESSED",
    },

    receivedAt: {
      S: order.receivedAt || now,
    },

    processedAt: {
      S: now,
    },
  };

  await dynamodb.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: item,
    })
  );

  console.log("Order persisted in DynamoDB", {
    orderId: order.orderId,
  });

  await eventBridge.send(
    new PutEventsCommand({
      Entries: [
        {
          EventBusName: EVENT_BUS_NAME,

          Source: "proj06.orders",

          DetailType: "OrderProcessed",

          Detail: JSON.stringify({
            orderId: order.orderId,
            customerId: order.customerId,
            status: "PROCESSED",
            processedAt: now,
          }),
        },
      ],
    })
  );

  console.log("OrderProcessed event published", {
    orderId: order.orderId,
  });
}

function validateOrder(order) {
  if (!order || typeof order !== "object") {
    throw new Error("Order must be an object");
  }

  if (!order.orderId) {
    throw new Error("Missing orderId");
  }

  if (!order.customerId) {
    throw new Error("Missing customerId");
  }

  if (!Array.isArray(order.items) || order.items.length === 0) {
    throw new Error("Order must contain at least one item");
  }
}
