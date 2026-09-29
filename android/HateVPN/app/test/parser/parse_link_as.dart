import 'package:lxbox/models/node_spec.dart';
import 'package:lxbox/services/parser/uri_parsers.dart';




T? parseLinkAs<T extends NodeSpec>(String uri) =>
    parseLinkViaPipeline(uri) as T?;
