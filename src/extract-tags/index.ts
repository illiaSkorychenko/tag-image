import { S3Handler } from 'aws-lambda';
import {
  RekognitionClient,
  DetectLabelsCommand,
  DetectLabelsCommandInput,
} from '@aws-sdk/client-rekognition';
import { DynamoDBClient, PutItemCommand, UpdateItemCommand } from '@aws-sdk/client-dynamodb';

const rekognitionClient = new RekognitionClient({
  region: process.env.AWS_REGION,
});
const dynamoDBClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const tableName = process.env.TABLE_NAME;

export const extractTags: S3Handler = async (event) => {
  if (!event.Records || event.Records.length > 1) {
    console.error('Wrong records amount, this lambda should be triggered by put event');

    return;
  }

  let canUpdateDb = false;
  const { bucket, object } = event.Records[0].s3;
  const params: DetectLabelsCommandInput = {
    Image: {
      S3Object: {
        Bucket: bucket.name,
        Name: object.key,
      },
    },
  };

  try {
    console.info('Inserting with PENDING');

    await dynamoDBClient.send(
      new PutItemCommand({
        TableName: tableName,
        Item: {
          uploadId: { S: object.key },
          status: { S: 'PENDING' },
        },
      })
    );
    canUpdateDb = true;

    console.info('Sending DetectLabelsCommand');

    const data = await rekognitionClient.send(new DetectLabelsCommand(params));

    if (!data.Labels) {
      throw new Error('No labels found');
    }

    const tags: string[] = [];

    for (const label of data.Labels) {
      if (!label?.Name) {
        continue;
      }

      tags.push(label.Name);
    }

    if (!tags.length) {
      throw new Error('No tags found');
    }

    console.log({ tags });

    console.info('Updating with COMPLETED');

    await dynamoDBClient.send(
      new UpdateItemCommand({
        TableName: tableName,
        Key: {
          uploadId: { S: object.key },
        },
        UpdateExpression: 'SET #tags = :tags, #status = :status',
        ExpressionAttributeNames: {
          '#tags': 'tags',
          '#status': 'status',
        },
        ExpressionAttributeValues: {
          ':tags': { SS: tags },
          ':status': { S: 'COMPLETED' },
        },
      })
    );
  } catch (error) {
    console.error(error);

    if (!canUpdateDb) {
      await dynamoDBClient.send(
        new PutItemCommand({
          TableName: tableName,
          Item: {
            uploadId: { S: object.key },
            status: { S: 'FAILED' },
          },
        })
      );

      return;
    }

    await dynamoDBClient.send(
      new UpdateItemCommand({
        TableName: tableName,
        Key: {
          uploadId: { S: object.key },
        },
        UpdateExpression: 'SET #status = :status',
        ExpressionAttributeNames: {
          '#status': 'status',
        },
        ExpressionAttributeValues: {
          ':status': { S: 'FAILED' },
        },
      })
    );
  }
};
