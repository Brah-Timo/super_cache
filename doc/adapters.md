# Custom Type Adapters

super_cache uses **adapters** to serialize any Dart type to binary.

## Built-in Adapters

Pre-registered automatically: `String?`, `int?`, `double?`, `bool?`,
`List<String>`, `List<int>`, `List<double>`, `List<bool>`,
`Map<String,String>`, `Map<String,int>`, `Map<String,dynamic>`,
`DateTime`, `Duration`, `Uri`, `BigInt`, `List<DateTime>`.

## Writing a Custom Adapter

```dart
class UserAdapter extends SuperCacheAdapter<User> {
  @override int get typeId => 1; // 0–220, unique in your project

  @override
  User read(BinaryReader reader) => User(
    id:   reader.readString(),
    name: reader.readString(),
    age:  reader.readInt32(),
  );

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name)
      ..writeInt32(obj.age);
  }
}
```

## Registering

Call **before** `SuperCache.init()`:

```dart
SuperCache.registerAdapter(UserAdapter());
await SuperCache.init(config: const CacheConfig());
```

## Type ID Rules

- Must be **0–220** (221–255 reserved by super_cache)
- Must be **unique** within your project
- Must **never change** across app versions (migration required otherwise)
