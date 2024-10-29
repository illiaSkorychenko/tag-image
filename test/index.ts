import * as fs from 'fs';
import { setTimeout } from 'timers/promises';

const API_ID = 'ci3e3d96pi';

async function main() {
  // const uploadLinkResp = await fetch(
  //   `https://${API_ID}.execute-api.eu-central-1.amazonaws.com/prod/upload-link`,
  //   {
  //     method: 'GET',
  //   }
  // );
  // const uploadLinkData: { uploadUrl: string; uploadId: string } = await uploadLinkResp.json();

  // console.log(uploadLinkData);

  // const testImage = fs.readFileSync('test_image.png');
  // await fetch(uploadLinkData.uploadUrl, {
  //   method: 'PUT',
  //   headers: {
  //     'Content-Type': 'image/png',
  //     'Content-Length': testImage.byteLength.toString(),
  //   },
  //   body: testImage,
  // });

  // await setTimeout(1000);

  // const uploadLinkData = {
  //   uploadId: '14952a64-7486-45f6-be2b-6cfa3fbfffe8',
  // };

  // const resp = await fetch(
  //   `https://${API_ID}.execute-api.eu-central-1.amazonaws.com/prod/status-tags?uploadId=${uploadLinkData.uploadId}`,
  //   {
  //     method: 'GET',
  //   }
  // );

  // const data = await resp.json();
  // console.log(data);

  process.exit(0);
}
main();
