import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { randomUUID } from 'node:crypto';
import { APIGatewayProxyHandlerV2 } from 'aws-lambda';

const s3Client = new S3Client({ region: process.env.AWS_REGION });

export const getUploadLink: APIGatewayProxyHandlerV2 = async () => {
  const uploadId = randomUUID();
  const command = new PutObjectCommand({
    Bucket: process.env.BUCKET_NAME,
    Key: uploadId,
  });
  const uploadUrl = await getSignedUrl(s3Client, command, { expiresIn: 3600 });

  return {
    statusCode: 200,
    body: JSON.stringify({ uploadUrl, uploadId }),
  };
};
