import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mime_type/mime_type.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'package:google_drive_client/src/file.dart';

class GoogleDriveClient {
  GoogleDriveSpace _space;
  Dio _dio;

  GoogleDriveClient(this._dio, {@required Future<String> Function() getAccessToken, GoogleDriveSpace space}) {
    _space = space ?? GoogleDriveSpace.appDataFolder;

    _dio.interceptors.add(InterceptorsWrapper(onRequest: (RequestOptions options,RequestInterceptorHandler requestInterceptorHandler) async {
      options.headers['Authorization'] = 'Bearer ${await getAccessToken.call()}';
      return options;
    }));

    _dio.options.validateStatus = (code) => code == 200 || code == 204;
  }

  /// list all google files base on space
  Future<List<GoogleDriveFileMetaData>> list() async {
    Response response = await _dio.get(
      'https://www.googleapis.com/drive/v3/files',
      queryParameters: {
        'fields':
            'files(id,name,kind,mimeType,description,properties,appProperties,spaces,createdTime,modifiedTime,size)',
        'spaces': _space == GoogleDriveSpace.appDataFolder ? 'appDataFolder' : null,
      },
    );

    return (response.data['files'] as List)
        .map(
          (file) => GoogleDriveFileMetaData(
            kind: file['kind'],
            id: file['id'],
            mimeType: file['mimeType'],
            description: file['description'],
            name: file['name'],
            properties: file['properties'],
            appProperties: file['appProperties'],
            spaces: List.castFrom(file['spaces']),
            createdTime: DateTime.tryParse(file['createdTime']),
            modifiedTime: DateTime.tryParse(file['modifiedTime']),
            size: file['size'] != null ? int.tryParse(file['size']) : null,
          ),
        )
        .toList();
  }

  /// get a google file meta data
  Future<GoogleDriveFileMetaData> get(String id) async {
    Response response = await _dio.get(
      'https://www.googleapis.com/drive/v3/files/$id',
      queryParameters: {
        'fields': 'id,name,kind,mimeType,description,properties,appProperties,spaces,createdTime,modifiedTime,size',
      },
    );

    var file = response.data;
    return GoogleDriveFileMetaData(
      kind: file['kind'],
      id: file['id'],
      mimeType: file['mimeType'],
      description: file['description'],
      name: file['name'],
      properties: file['properties'],
      appProperties: file['appProperties'],
      spaces: List.castFrom(file['spaces']),
      createdTime: DateTime.tryParse(file['createdTime']),
      modifiedTime: DateTime.tryParse(file['modifiedTime']),
      size: file['size'] != null ? int.tryParse(file['size']) : null,
    );
  }

  /// create a google file
  Future<GoogleDriveFileMetaData> create(GoogleDriveFileUploadMetaData metaData, File file,
      {Function(int, int) onUploadProgress}) async {
    Response metaResponse = await _dio.post(
      'https://www.googleapis.com/upload/drive/v3/files',
      queryParameters: {
        'uploadType': 'resumable',
      },
      data: {
        'parents': _space == GoogleDriveSpace.appDataFolder ? ['appDataFolder'] : null,
        'properties': metaData.properties,
        'appProperties': metaData.appProperties,
        'description': metaData.description,
        'name': metaData.name,
        'mimeType': mime(file.path),
      },
    );

    String uploadUrl = metaResponse.headers.value('Location');
    Response uploadResponse = await _dio.put(
      uploadUrl,
      options: Options(headers: {'Content-Length': file.lengthSync()}),
      data: file.openRead(),
      onSendProgress: (count, total) => onUploadProgress?.call(count, total),
    );
    return await get(uploadResponse.data['id']);
  }

  /// download a google file
  Future<File> download(String id, String filename, {Function(int, int) onDownloadProgress}) async {
    String path = join((await getTemporaryDirectory()).path, filename);
    await _dio.download(
      'https://www.googleapis.com/drive/v3/files/$id',
      path,
      queryParameters: {
        'alt': 'media',
      },
      options: Options(headers: {HttpHeaders.acceptEncodingHeader: "*"}),
      onReceiveProgress: (count, total) => onDownloadProgress?.call(count, total),
    );
    return File(path);
  }

  /// delete a google file
  Future<void> delete(String id) async {
    await _dio.delete('https://www.googleapis.com/drive/v3/files/$id');
  }
}
