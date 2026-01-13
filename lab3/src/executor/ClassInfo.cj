package cjcj.executor
import std.collection.*
public class ClassInfo {
    public let name: String
    public let fields = HashMap<String, StaticType>()
    public let fieldInitialized = HashMap<String, Bool>()
    public let methods = HashMap<String, StaticType>()  // name -> TFunc
    public var ctor: Option<StaticType> = Option.None   // 构造函数签名

    public init(name: String) {
        this.name = name
    }
}


