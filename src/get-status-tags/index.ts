import { APIGatewayProxyHandlerV2 } from 'aws-lambda';
import { DynamoDBClient, GetItemCommand } from '@aws-sdk/client-dynamodb';

const dynamoDBClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const tableName = process.env.TABLE_NAME;

export const getStatusAndTags: APIGatewayProxyHandlerV2 = async (event) => {
  try {
    if (!event.queryStringParameters?.uploadId) {
      console.error('Missing uploadId');

      return {
        statusCode: 400,
        body: JSON.stringify({ message: 'Missing uploadId' }),
      };
    }

    const uploadId = event.queryStringParameters?.uploadId;
    const result = await dynamoDBClient.send(
      new GetItemCommand({
        TableName: tableName,
        Key: { uploadId: { S: uploadId } },
      })
    );

    return {
      statusCode: 200,
      body: JSON.stringify(result.Item || null),
    };
  } catch (err) {
    console.error(err);

    return {
      statusCode: 400,
      body: JSON.stringify({ message: 'Error getting status and tags' }),
    };
  }
};
