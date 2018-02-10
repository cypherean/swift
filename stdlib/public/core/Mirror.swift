//===--- Mirror.swift -----------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// FIXME: ExistentialCollection needs to be supported before this will work
// without the ObjC Runtime.

/// A representation of the substructure and display style of an instance of
/// any type.
///
/// A mirror describes the parts that make up a particular instance, such as
/// the instance's stored properties, collection or tuple elements, or its
/// active enumeration case. Mirrors also provide a "display style" property
/// that suggests how this mirror might be rendered.
///
/// Playgrounds and the debugger use the `Mirror` type to display
/// representations of values of any type. For example, when you pass an
/// instance to the `dump(_:_:_:_:)` function, a mirror is used to render that
/// instance's runtime contents.
///
///     struct Point {
///         let x: Int, y: Int
///     }
///
///     let p = Point(x: 21, y: 30)
///     print(String(reflecting: p))
///     // Prints "▿ Point
///     //           - x: 21
///     //           - y: 30"
///
/// To customize the mirror representation of a custom type, add conformance to
/// the `CustomReflectable` protocol.
@_fixed_layout // FIXME(sil-serialize-all)
public struct Mirror {
  /// Representation of descendant classes that don't override
  /// `customMirror`.
  ///
  /// Note that the effect of this setting goes no deeper than the
  /// nearest descendant class that overrides `customMirror`, which
  /// in turn can determine representation of *its* descendants.
  @_frozen // FIXME(sil-serialize-all)
  @_versioned // FIXME(sil-serialize-all)
  internal enum _DefaultDescendantRepresentation {
    /// Generate a default mirror for descendant classes that don't
    /// override `customMirror`.
    ///
    /// This case is the default.
    case generated

    /// Suppress the representation of descendant classes that don't
    /// override `customMirror`.
    ///
    /// This option may be useful at the root of a class cluster, where
    /// implementation details of descendants should generally not be
    /// visible to clients.
    case suppressed
  }

  /// The representation to use for ancestor classes.
  ///
  /// A class that conforms to the `CustomReflectable` protocol can control how
  /// its mirror represents ancestor classes by initializing the mirror
  /// with an `AncestorRepresentation`. This setting has no effect on mirrors
  /// reflecting value type instances.
  public enum AncestorRepresentation {

    /// Generates a default mirror for all ancestor classes.
    ///
    /// This case is the default when initializing a `Mirror` instance.
    ///
    /// When you use this option, a subclass's mirror generates default mirrors
    /// even for ancestor classes that conform to the `CustomReflectable`
    /// protocol. To avoid dropping the customization provided by ancestor
    /// classes, an override of `customMirror` should pass
    /// `.customized({ super.customMirror })` as `ancestorRepresentation` when
    /// initializing its mirror.
    case generated

    /// Uses the nearest ancestor's implementation of `customMirror` to create
    /// a mirror for that ancestor.
    ///
    /// Other classes derived from such an ancestor are given a default mirror.
    /// The payload for this option should always be `{ super.customMirror }`:
    ///
    ///     var customMirror: Mirror {
    ///         return Mirror(
    ///             self,
    ///             children: ["someProperty": self.someProperty],
    ///             ancestorRepresentation: .customized({ super.customMirror })) // <==
    ///     }
    case customized(() -> Mirror)

    /// Suppresses the representation of all ancestor classes.
    ///
    /// In a mirror created with this ancestor representation, the
    /// `superclassMirror` property is `nil`.
    case suppressed
  }

  /// Creates a mirror that reflects on the given instance.
  ///
  /// If the dynamic type of `subject` conforms to `CustomReflectable`, the
  /// resulting mirror is determined by its `customMirror` property.
  /// Otherwise, the result is generated by the language.
  ///
  /// If the dynamic type of `subject` has value semantics, subsequent
  /// mutations of `subject` will not observable in `Mirror`.  In general,
  /// though, the observability of mutations is unspecified.
  ///
  /// - Parameter subject: The instance for which to create a mirror.
  @_inlineable // FIXME(sil-serialize-all)
  public init(reflecting subject: Any) {
    if case let customized as CustomReflectable = subject {
      self = customized.customMirror
    } else {
      self = Mirror(internalReflecting: subject)
    }
  }

  /// An element of the reflected instance's structure.
  ///
  /// When the `label` component in not `nil`, it may represent the name of a
  /// stored property or an active `enum` case. If you pass strings to the
  /// `descendant(_:_:)` method, labels are used for lookup.
  public typealias Child = (label: String?, value: Any)

  /// The type used to represent substructure.
  ///
  /// When working with a mirror that reflects a bidirectional or random access
  /// collection, you may find it useful to "upgrade" instances of this type
  /// to `AnyBidirectionalCollection` or `AnyRandomAccessCollection`. For
  /// example, to display the last twenty children of a mirror if they can be
  /// accessed efficiently, you write the following code:
  ///
  ///     if let b = AnyBidirectionalCollection(someMirror.children) {
  ///         for element in b.suffix(20) {
  ///             print(element)
  ///         }
  ///     }
  public typealias Children = AnyCollection<Child>

  /// A suggestion of how a mirror's subject is to be interpreted.
  ///
  /// Playgrounds and the debugger will show a representation similar
  /// to the one used for instances of the kind indicated by the
  /// `DisplayStyle` case name when the mirror is used for display.
  public enum DisplayStyle {
    case `struct`, `class`, `enum`, tuple, optional, collection
    case dictionary, `set`
  }

  @_inlineable // FIXME(sil-serialize-all)
  @_versioned // FIXME(sil-serialize-all)
  internal static func _noSuperclassMirror() -> Mirror? { return nil }

  @_semantics("optimize.sil.specialize.generic.never")
  @inline(never)
  @_inlineable // FIXME(sil-serialize-all)
  @_versioned
  internal static func _superclassIterator<Subject>(
    _ subject: Subject, _ ancestorRepresentation: AncestorRepresentation
  ) -> () -> Mirror? {

    if let subjectClass = Subject.self as? AnyClass,
       let superclass = _getSuperclass(subjectClass) {

      switch ancestorRepresentation {
      case .generated:
        return {
          Mirror(internalReflecting: subject, subjectType: superclass)
        }
      case .customized(let makeAncestor):
        return {
          let ancestor = makeAncestor()
          if superclass == ancestor.subjectType
            || ancestor._defaultDescendantRepresentation == .suppressed {
            return ancestor
          } else {
            return Mirror(internalReflecting: subject,
                          subjectType: superclass,
                          customAncestor: ancestor)
          }
        }
      case .suppressed:
        break
      }
    }
    return Mirror._noSuperclassMirror
  }
  
  /// Creates a mirror representing the given subject with a specified
  /// structure.
  ///
  /// You use this initializer from within your type's `customMirror`
  /// implementation to create a customized mirror.
  ///
  /// If `subject` is a class instance, `ancestorRepresentation` determines
  /// whether ancestor classes will be represented and whether their
  /// `customMirror` implementations will be used. By default, the
  /// `customMirror` implementation of any ancestors is ignored. To prevent
  /// bypassing customized ancestors, pass
  /// `.customized({ super.customMirror })` as the `ancestorRepresentation`
  /// parameter when implementing your type's `customMirror` property.
  ///
  /// - Parameters:
  ///   - subject: The instance to represent in the new mirror.
  ///   - children: The structure to use for the mirror. The collection
  ///     traversal modeled by `children` is captured so that the resulting
  ///     mirror's children may be upgraded to a bidirectional or random
  ///     access collection later. See the `children` property for details.
  ///   - displayStyle: The preferred display style for the mirror when
  ///     presented in the debugger or in a playground. The default is `nil`.
  ///   - ancestorRepresentation: The means of generating the subject's
  ///     ancestor representation. `ancestorRepresentation` is ignored if
  ///     `subject` is not a class instance. The default is `.generated`.
  @_inlineable // FIXME(sil-serialize-all)
  public init<Subject, C : Collection>(
    _ subject: Subject,
    children: C,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .generated
  ) where C.Element == Child 
  {

    self.subjectType = Subject.self
    self._makeSuperclassMirror = Mirror._superclassIterator(
      subject, ancestorRepresentation)
      
    self.children = Children(children)
    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation
      = subject is CustomLeafReflectable ? .suppressed : .generated
  }

  /// Creates a mirror representing the given subject with unlabeled children.
  ///
  /// You use this initializer from within your type's `customMirror`
  /// implementation to create a customized mirror, particularly for custom
  /// types that are collections. The labels of the resulting mirror's
  /// `children` collection are all `nil`.
  ///
  /// If `subject` is a class instance, `ancestorRepresentation` determines
  /// whether ancestor classes will be represented and whether their
  /// `customMirror` implementations will be used. By default, the
  /// `customMirror` implementation of any ancestors is ignored. To prevent
  /// bypassing customized ancestors, pass
  /// `.customized({ super.customMirror })` as the `ancestorRepresentation`
  /// parameter when implementing your type's `customMirror` property.
  ///
  /// - Parameters:
  ///   - subject: The instance to represent in the new mirror.
  ///   - unlabeledChildren: The children to use for the mirror. The collection
  ///     traversal modeled by `unlabeledChildren` is captured so that the
  ///     resulting mirror's children may be upgraded to a bidirectional or
  ///     random access collection later. See the `children` property for
  ///     details.
  ///   - displayStyle: The preferred display style for the mirror when
  ///     presented in the debugger or in a playground. The default is `nil`.
  ///   - ancestorRepresentation: The means of generating the subject's
  ///     ancestor representation. `ancestorRepresentation` is ignored if
  ///     `subject` is not a class instance. The default is `.generated`.
  @_inlineable // FIXME(sil-serialize-all)
  public init<Subject, C : Collection>(
    _ subject: Subject,
    unlabeledChildren: C,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .generated
  ) 
  {

    self.subjectType = Subject.self
    self._makeSuperclassMirror = Mirror._superclassIterator(
      subject, ancestorRepresentation)
      
    let lazyChildren =
      unlabeledChildren.lazy.map { Child(label: nil, value: $0) }
    self.children = Children(lazyChildren)

    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation
      = subject is CustomLeafReflectable ? .suppressed : .generated
  }

  /// Creates a mirror representing the given subject using a dictionary
  /// literal for the structure.
  ///
  /// You use this initializer from within your type's `customMirror`
  /// implementation to create a customized mirror. Pass a dictionary literal
  /// with string keys as `children`. Although an *actual* dictionary is
  /// arbitrarily-ordered, when you create a mirror with a dictionary literal,
  /// the ordering of the mirror's `children` will exactly match that of the
  /// literal you pass.
  ///
  /// If `subject` is a class instance, `ancestorRepresentation` determines
  /// whether ancestor classes will be represented and whether their
  /// `customMirror` implementations will be used. By default, the
  /// `customMirror` implementation of any ancestors is ignored. To prevent
  /// bypassing customized ancestors, pass
  /// `.customized({ super.customMirror })` as the `ancestorRepresentation`
  /// parameter when implementing your type's `customMirror` property.
  ///
  /// - Parameters:
  ///   - subject: The instance to represent in the new mirror.
  ///   - children: A dictionary literal to use as the structure for the
  ///     mirror. The `children` collection of the resulting mirror may be
  ///     upgraded to a random access collection later. See the `children`
  ///     property for details.
  ///   - displayStyle: The preferred display style for the mirror when
  ///     presented in the debugger or in a playground. The default is `nil`.
  ///   - ancestorRepresentation: The means of generating the subject's
  ///     ancestor representation. `ancestorRepresentation` is ignored if
  ///     `subject` is not a class instance. The default is `.generated`.
  @_inlineable // FIXME(sil-serialize-all)
  public init<Subject>(
    _ subject: Subject,
    children: DictionaryLiteral<String, Any>,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .generated
  ) {
    self.subjectType = Subject.self
    self._makeSuperclassMirror = Mirror._superclassIterator(
      subject, ancestorRepresentation)
      
    let lazyChildren = children.lazy.map { Child(label: $0.0, value: $0.1) }
    self.children = Children(lazyChildren)

    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation
      = subject is CustomLeafReflectable ? .suppressed : .generated
  }

  /// The static type of the subject being reflected.
  ///
  /// This type may differ from the subject's dynamic type when this mirror
  /// is the `superclassMirror` of another mirror.
  public let subjectType: Any.Type

  /// A collection of `Child` elements describing the structure of the
  /// reflected subject.
  public let children: Children

  /// A suggested display style for the reflected subject.
  public let displayStyle: DisplayStyle?

  /// A mirror of the subject's superclass, if one exists.
  @_inlineable // FIXME(sil-serialize-all)
  public var superclassMirror: Mirror? {
    return _makeSuperclassMirror()
  }

  @_versioned // FIXME(sil-serialize-all)
  internal let _makeSuperclassMirror: () -> Mirror?
  @_versioned // FIXME(sil-serialize-all)
  internal let _defaultDescendantRepresentation: _DefaultDescendantRepresentation
}

/// A type that explicitly supplies its own mirror.
///
/// You can create a mirror for any type using the `Mirror(reflecting:)`
/// initializer, but if you are not satisfied with the mirror supplied for
/// your type by default, you can make it conform to `CustomReflectable` and
/// return a custom `Mirror` instance.
public protocol CustomReflectable {
  /// The custom mirror for this instance.
  ///
  /// If this type has value semantics, the mirror should be unaffected by
  /// subsequent mutations of the instance.
  var customMirror: Mirror { get }
}

/// A type that explicitly supplies its own mirror, but whose
/// descendant classes are not represented in the mirror unless they
/// also override `customMirror`.
public protocol CustomLeafReflectable : CustomReflectable {}

//===--- Addressing -------------------------------------------------------===//

/// A protocol for legitimate arguments to `Mirror`'s `descendant`
/// method.
///
/// Do not declare new conformances to this protocol; they will not
/// work as expected.
public protocol MirrorPath {
  // FIXME(ABI)#49 (Sealed Protocols): this protocol should be "non-open" and
  // you shouldn't be able to create conformances.
}
extension Int : MirrorPath {}
extension String : MirrorPath {}

extension Mirror {
  @_fixed_layout // FIXME(sil-serialize-all)
  @_versioned // FIXME(sil-serialize-all)
  internal struct _Dummy : CustomReflectable {
    @_inlineable // FIXME(sil-serialize-all)
    @_versioned // FIXME(sil-serialize-all)
    internal init(mirror: Mirror) {
      self.mirror = mirror
    }
    @_versioned // FIXME(sil-serialize-all)
    internal var mirror: Mirror
    @_inlineable // FIXME(sil-serialize-all)
    @_versioned // FIXME(sil-serialize-all)
    internal var customMirror: Mirror { return mirror }
  }

  /// Returns a specific descendant of the reflected subject, or `nil` if no
  /// such descendant exists.
  ///
  /// Pass a variadic list of string and integer arguments. Each string
  /// argument selects the first child with a matching label. Each integer
  /// argument selects the child at that offset. For example, passing
  /// `1, "two", 3` as arguments to `myMirror.descendant(_:_:)` is equivalent
  /// to:
  ///
  ///     var result: Any? = nil
  ///     let children = myMirror.children
  ///     if let i0 = children.index(
  ///         children.startIndex, offsetBy: 1, limitedBy: children.endIndex),
  ///         i0 != children.endIndex
  ///     {
  ///         let grandChildren = Mirror(reflecting: children[i0].value).children
  ///         if let i1 = grandChildren.index(where: { $0.label == "two" }) {
  ///             let greatGrandChildren =
  ///                 Mirror(reflecting: grandChildren[i1].value).children
  ///             if let i2 = greatGrandChildren.index(
  ///                 greatGrandChildren.startIndex,
  ///                 offsetBy: 3,
  ///                 limitedBy: greatGrandChildren.endIndex),
  ///                 i2 != greatGrandChildren.endIndex
  ///             {
  ///                 // Success!
  ///                 result = greatGrandChildren[i2].value
  ///             }
  ///         }
  ///     }
  ///
  /// This function is suitable for exploring the structure of a mirror in a
  /// REPL or playground, but is not intended to be efficient. The efficiency
  /// of finding each element in the argument list depends on the argument
  /// type and the capabilities of the each level of the mirror's `children`
  /// collections. Each string argument requires a linear search, and unless
  /// the underlying collection supports random-access traversal, each integer
  /// argument also requires a linear operation.
  ///
  /// - Parameters:
  ///   - first: The first mirror path component to access.
  ///   - rest: Any remaining mirror path components.
  /// - Returns: The descendant of this mirror specified by the given mirror
  ///   path components if such a descendant exists; otherwise, `nil`.
  @_inlineable // FIXME(sil-serialize-all)
  public func descendant(
    _ first: MirrorPath, _ rest: MirrorPath...
  ) -> Any? {
    var result: Any = _Dummy(mirror: self)
    for e in [first] + rest {
      let children = Mirror(reflecting: result).children
      let position: Children.Index
      if case let label as String = e {
        position = children.index { $0.label == label } ?? children.endIndex
      }
      else if let offset = e as? Int {
        position = children.index(children.startIndex,
          offsetBy: offset,
          limitedBy: children.endIndex) ?? children.endIndex
      }
      else {
        _preconditionFailure(
          "Someone added a conformance to MirrorPath; that privilege is reserved to the standard library")
      }
      if position == children.endIndex { return nil }
      result = children[position].value
    }
    return result
  }
}

//===--- QuickLooks -------------------------------------------------------===//

/// The sum of types that can be used as a Quick Look representation.
///
/// The `PlaygroundQuickLook` protocol is deprecated, and will be removed from
/// the standard library in a future Swift release. To customize the logging of
/// your type in a playground, conform to the
/// `CustomPlaygroundDisplayConvertible` protocol, which does not use the
/// `PlaygroundQuickLook` enum.
///
/// If you need to provide a customized playground representation in Swift 4.0
/// or Swift 3.2 or earlier, use a conditional compilation block:
///
///     #if swift(>=4.1) || (swift(>=3.3) && !swift(>=4.0))
///         // With Swift 4.1 and later (including Swift 3.3 and later), use
///         // the CustomPlaygroundDisplayConvertible protocol.
///     #else
///         // With Swift 4.0 and Swift 3.2 and earlier, use PlaygroundQuickLook
///         // and the CustomPlaygroundQuickLookable protocol.
///     #endif
@_frozen // rdar://problem/38719739 - needed by LLDB
@available(*, deprecated, message: "PlaygroundQuickLook will be removed in a future Swift version. For customizing how types are presented in playgrounds, use CustomPlaygroundDisplayConvertible instead.")
public enum PlaygroundQuickLook {
  /// Plain text.
  case text(String)

  /// An integer numeric value.
  case int(Int64)

  /// An unsigned integer numeric value.
  case uInt(UInt64)

  /// A single precision floating-point numeric value.
  case float(Float32)

  /// A double precision floating-point numeric value.
  case double(Float64)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// An image.
  case image(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A sound.
  case sound(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A color.
  case color(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A bezier path.
  case bezierPath(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// An attributed string.
  case attributedString(Any)

  // FIXME: Uses explicit coordinates to avoid coupling a particular Cocoa type.
  /// A rectangle.
  case rectangle(Float64, Float64, Float64, Float64)

  // FIXME: Uses explicit coordinates to avoid coupling a particular Cocoa type.
  /// A point.
  case point(Float64, Float64)

  // FIXME: Uses explicit coordinates to avoid coupling a particular Cocoa type.
  /// A size.
  case size(Float64, Float64)

  /// A boolean value.
  case bool(Bool)

  // FIXME: Uses explicit values to avoid coupling a particular Cocoa type.
  /// A range.
  case range(Int64, Int64)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A GUI view.
  case view(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A graphical sprite.
  case sprite(Any)

  /// A Uniform Resource Locator.
  case url(String)

  /// Raw data that has already been encoded in a format the IDE understands.
  case _raw([UInt8], String)
}

extension PlaygroundQuickLook {
  /// Creates a new Quick Look for the given instance.
  ///
  /// If the dynamic type of `subject` conforms to
  /// `CustomPlaygroundQuickLookable`, the result is found by calling its
  /// `customPlaygroundQuickLook` property. Otherwise, the result is
  /// synthesized by the language. In some cases, the synthesized result may
  /// be `.text(String(reflecting: subject))`.
  ///
  /// - Note: If the dynamic type of `subject` has value semantics, subsequent
  ///   mutations of `subject` will not observable in the Quick Look. In
  ///   general, though, the observability of such mutations is unspecified.
  ///
  /// - Parameter subject: The instance to represent with the resulting Quick
  ///   Look.
  @_inlineable // FIXME(sil-serialize-all)
  @available(*, deprecated, message: "PlaygroundQuickLook will be removed in a future Swift version.")
  public init(reflecting subject: Any) {
    if let customized = subject as? CustomPlaygroundQuickLookable {
      self = customized.customPlaygroundQuickLook
    }
    else if let customized = subject as? _DefaultCustomPlaygroundQuickLookable {
      self = customized._defaultCustomPlaygroundQuickLook
    }
    else {
      if let q = Mirror.quickLookObject(subject) {
        self = q
      }
      else {
        self = .text(String(reflecting: subject))
      }
    }
  }
}

/// A type that explicitly supplies its own playground Quick Look.
///
/// The `CustomPlaygroundQuickLookable` protocol is deprecated, and will be
/// removed from the standard library in a future Swift release. To customize
/// the logging of your type in a playground, conform to the
/// `CustomPlaygroundDisplayConvertible` protocol.
///
/// If you need to provide a customized playground representation in Swift 4.0
/// or Swift 3.2 or earlier, use a conditional compilation block:
///
///     #if swift(>=4.1) || (swift(>=3.3) && !swift(>=4.0))
///         // With Swift 4.1 and later (including Swift 3.3 and later),
///         // conform to CustomPlaygroundDisplayConvertible.
///         extension MyType: CustomPlaygroundDisplayConvertible { /*...*/ }
///     #else
///         // Otherwise, on Swift 4.0 and Swift 3.2 and earlier,
///         // conform to CustomPlaygroundQuickLookable.
///         extension MyType: CustomPlaygroundQuickLookable { /*...*/ }
///     #endif
@available(*, deprecated, message: "CustomPlaygroundQuickLookable will be removed in a future Swift version. For customizing how types are presented in playgrounds, use CustomPlaygroundDisplayConvertible instead.")
public protocol CustomPlaygroundQuickLookable {
  /// A custom playground Quick Look for this instance.
  ///
  /// If this type has value semantics, the `PlaygroundQuickLook` instance
  /// should be unaffected by subsequent mutations.
  var customPlaygroundQuickLook: PlaygroundQuickLook { get }
}


// A workaround for <rdar://problem/26182650>
// FIXME(ABI)#50 (Dynamic Dispatch for Class Extensions) though not if it moves out of stdlib.
@available(*, deprecated, message: "_DefaultCustomPlaygroundQuickLookable will be removed in a future Swift version. For customizing how types are presented in playgrounds, use CustomPlaygroundDisplayConvertible instead.")
public protocol _DefaultCustomPlaygroundQuickLookable {
  var _defaultCustomPlaygroundQuickLook: PlaygroundQuickLook { get }
}

//===--- General Utilities ------------------------------------------------===//
// This component could stand alone, but is used in Mirror's public interface.

/// A lightweight collection of key-value pairs.
///
/// Use a `DictionaryLiteral` instance when you need an ordered collection of
/// key-value pairs and don't require the fast key lookup that the
/// `Dictionary` type provides. Unlike key-value pairs in a true dictionary,
/// neither the key nor the value of a `DictionaryLiteral` instance must
/// conform to the `Hashable` protocol.
///
/// You initialize a `DictionaryLiteral` instance using a Swift dictionary
/// literal. Besides maintaining the order of the original dictionary literal,
/// `DictionaryLiteral` also allows duplicates keys. For example:
///
///     let recordTimes: DictionaryLiteral = ["Florence Griffith-Joyner": 10.49,
///                                           "Evelyn Ashford": 10.76,
///                                           "Evelyn Ashford": 10.79,
///                                           "Marlies Gohr": 10.81]
///     print(recordTimes.first!)
///     // Prints "("Florence Griffith-Joyner", 10.49)"
///
/// Some operations that are efficient on a dictionary are slower when using
/// `DictionaryLiteral`. In particular, to find the value matching a key, you
/// must search through every element of the collection. The call to
/// `index(where:)` in the following example must traverse the whole
/// collection to find the element that matches the predicate:
///
///     let runner = "Marlies Gohr"
///     if let index = recordTimes.index(where: { $0.0 == runner }) {
///         let time = recordTimes[index].1
///         print("\(runner) set a 100m record of \(time) seconds.")
///     } else {
///         print("\(runner) couldn't be found in the records.")
///     }
///     // Prints "Marlies Gohr set a 100m record of 10.81 seconds."
///
/// Dictionary Literals as Function Parameters
/// ------------------------------------------
///
/// When calling a function with a `DictionaryLiteral` parameter, you can pass
/// a Swift dictionary literal without causing a `Dictionary` to be created.
/// This capability can be especially important when the order of elements in
/// the literal is significant.
///
/// For example, you could create an `IntPairs` structure that holds a list of
/// two-integer tuples and use an initializer that accepts a
/// `DictionaryLiteral` instance.
///
///     struct IntPairs {
///         var elements: [(Int, Int)]
///
///         init(_ elements: DictionaryLiteral<Int, Int>) {
///             self.elements = Array(elements)
///         }
///     }
///
/// When you're ready to create a new `IntPairs` instance, use a dictionary
/// literal as the parameter to the `IntPairs` initializer. The
/// `DictionaryLiteral` instance preserves the order of the elements as
/// passed.
///
///     let pairs = IntPairs([1: 2, 1: 1, 3: 4, 2: 1])
///     print(pairs.elements)
///     // Prints "[(1, 2), (1, 1), (3, 4), (2, 1)]"
@_fixed_layout // FIXME(sil-serialize-all)
public struct DictionaryLiteral<Key, Value> : ExpressibleByDictionaryLiteral {
  /// Creates a new `DictionaryLiteral` instance from the given dictionary
  /// literal.
  ///
  /// The order of the key-value pairs is kept intact in the resulting
  /// `DictionaryLiteral` instance.
  @_inlineable // FIXME(sil-serialize-all)
  public init(dictionaryLiteral elements: (Key, Value)...) {
    self._elements = elements
  }
  @_versioned // FIXME(sil-serialize-all)
  internal let _elements: [(Key, Value)]
}

/// `Collection` conformance that allows `DictionaryLiteral` to
/// interoperate with the rest of the standard library.
extension DictionaryLiteral : RandomAccessCollection {
  public typealias Indices = Range<Int>
  
  /// The position of the first element in a nonempty collection.
  ///
  /// If the `DictionaryLiteral` instance is empty, `startIndex` is equal to
  /// `endIndex`.
  @_inlineable // FIXME(sil-serialize-all)
  public var startIndex: Int { return 0 }

  /// The collection's "past the end" position---that is, the position one
  /// greater than the last valid subscript argument.
  ///
  /// If the `DictionaryLiteral` instance is empty, `endIndex` is equal to
  /// `startIndex`.
  @_inlineable // FIXME(sil-serialize-all)
  public var endIndex: Int { return _elements.endIndex }

  // FIXME(ABI)#174 (Type checker): a typealias is needed to prevent <rdar://20248032>
  /// The element type of a `DictionaryLiteral`: a tuple containing an
  /// individual key-value pair.
  public typealias Element = (key: Key, value: Value)

  /// Accesses the element at the specified position.
  ///
  /// - Parameter position: The position of the element to access. `position`
  ///   must be a valid index of the collection that is not equal to the
  ///   `endIndex` property.
  /// - Returns: The key-value pair at position `position`.
  @_inlineable // FIXME(sil-serialize-all)
  public subscript(position: Int) -> Element {
    return _elements[position]
  }
}

extension DictionaryLiteral: Equatable where Key: Equatable, Value: Equatable {
  @_inlineable // FIXME(sil-serialize-all)
  public static func == (
    lhs: DictionaryLiteral<Key, Value>, rhs: DictionaryLiteral<Key, Value>
  ) -> Bool {
    if lhs.count != rhs.count {
      return false
    }
    return lhs.elementsEqual(rhs, by: ==)
  }
}

extension DictionaryLiteral: Hashable where Key: Hashable, Value: Hashable {
  /// The hash value for the collection.
  ///
  /// Two `DictionaryLiteral` values that are equal will always have equal hash
  /// values.
  ///
  /// Hash values are not guaranteed to be equal across different executions of
  /// your program. Do not save hash values to use during a future execution.
  @_inlineable // FIXME(sil-serialize-all)
  public var hashValue: Int {
    // FIXME(ABI)#177: <rdar://problem/18915294> Issue applies to DictionaryLiteral too
    var result: Int = 0
    for element in self {
      let elementHashValue =
        _combineHashValues(element.key.hashValue, element.value.hashValue)
      result = _combineHashValues(result, elementHashValue)
    }
    return result
  }
}

extension String {
  /// Creates a string representing the given value.
  ///
  /// Use this initializer to convert an instance of any type to its preferred
  /// representation as a `String` instance. The initializer creates the
  /// string representation of `instance` in one of the following ways,
  /// depending on its protocol conformance:
  ///
  /// - If `instance` conforms to the `TextOutputStreamable` protocol, the
  ///   result is obtained by calling `instance.write(to: s)` on an empty
  ///   string `s`.
  /// - If `instance` conforms to the `CustomStringConvertible` protocol, the
  ///   result is `instance.description`.
  /// - If `instance` conforms to the `CustomDebugStringConvertible` protocol,
  ///   the result is `instance.debugDescription`.
  /// - An unspecified result is supplied automatically by the Swift standard
  ///   library.
  ///
  /// For example, this custom `Point` struct uses the default representation
  /// supplied by the standard library.
  ///
  ///     struct Point {
  ///         let x: Int, y: Int
  ///     }
  ///
  ///     let p = Point(x: 21, y: 30)
  ///     print(String(describing: p))
  ///     // Prints "Point(x: 21, y: 30)"
  ///
  /// After adding `CustomStringConvertible` conformance by implementing the
  /// `description` property, `Point` provides its own custom representation.
  ///
  ///     extension Point: CustomStringConvertible {
  ///         var description: String {
  ///             return "(\(x), \(y))"
  ///         }
  ///     }
  ///
  ///     print(String(describing: p))
  ///     // Prints "(21, 30)"
  @_inlineable // FIXME(sil-serialize-all)
  public init<Subject>(describing instance: Subject) {
    self.init()
    _print_unlocked(instance, &self)
  }

  /// Creates a string with a detailed representation of the given value,
  /// suitable for debugging.
  ///
  /// Use this initializer to convert an instance of any type to its custom
  /// debugging representation. The initializer creates the string
  /// representation of `instance` in one of the following ways, depending on
  /// its protocol conformance:
  ///
  /// - If `subject` conforms to the `CustomDebugStringConvertible` protocol,
  ///   the result is `subject.debugDescription`.
  /// - If `subject` conforms to the `CustomStringConvertible` protocol, the
  ///   result is `subject.description`.
  /// - If `subject` conforms to the `TextOutputStreamable` protocol, the
  ///   result is obtained by calling `subject.write(to: s)` on an empty
  ///   string `s`.
  /// - An unspecified result is supplied automatically by the Swift standard
  ///   library.
  ///
  /// For example, this custom `Point` struct uses the default representation
  /// supplied by the standard library.
  ///
  ///     struct Point {
  ///         let x: Int, y: Int
  ///     }
  ///
  ///     let p = Point(x: 21, y: 30)
  ///     print(String(reflecting: p))
  ///     // Prints "p: Point = {
  ///     //           x = 21
  ///     //           y = 30
  ///     //         }"
  ///
  /// After adding `CustomDebugStringConvertible` conformance by implementing
  /// the `debugDescription` property, `Point` provides its own custom
  /// debugging representation.
  ///
  ///     extension Point: CustomDebugStringConvertible {
  ///         var debugDescription: String {
  ///             return "Point(x: \(x), y: \(y))"
  ///         }
  ///     }
  ///
  ///     print(String(reflecting: p))
  ///     // Prints "Point(x: 21, y: 30)"
  @_inlineable // FIXME(sil-serialize-all)
  public init<Subject>(reflecting subject: Subject) {
    self.init()
    _debugPrint_unlocked(subject, &self)
  }
}

/// Reflection for `Mirror` itself.
extension Mirror : CustomStringConvertible {
  @_inlineable // FIXME(sil-serialize-all)
  public var description: String {
    return "Mirror for \(self.subjectType)"
  }
}

extension Mirror : CustomReflectable {
  @_inlineable // FIXME(sil-serialize-all)
  public var customMirror: Mirror {
    return Mirror(self, children: [:])
  }
}
