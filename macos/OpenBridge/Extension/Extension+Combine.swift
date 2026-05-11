//
//  Extension+Combine.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/1/7.
//

@preconcurrency import Combine

extension Publisher {
    func ensureMainThread() -> AnyPublisher<Output, Failure> {
        flatMap { value -> AnyPublisher<Output, Failure> in
            if Thread.isMainThread {
                return Just(value)
                    .setFailureType(to: Failure.self)
                    .eraseToAnyPublisher()
            } else {
                return Just(value)
                    .delay(for: .zero, scheduler: DispatchQueue.main)
                    .setFailureType(to: Failure.self)
                    .eraseToAnyPublisher()
            }
        }
        .eraseToAnyPublisher()
    }
}

/*

 下面两个方法设计为 Main Thread Only 时因为
    捕捉的对象 self 大多数情况下是 MainActor
    如果不使用 ensureMainThread 容易导致崩溃
    且抓不到调用信息

 如果 Publisher map 要转换数据 处理数据 可以考虑在 sink 里面做
    使用 Task.detached
    对于捕捉处理数据使用防止重复的 token 之类的机制 用 await MainActor.run { }

 */

extension Publisher where Failure == Never {
    func sinkOnMainWith<T: AnyObject>(_ target: T, receiveValue: @escaping @MainActor (T, Output) -> Void) -> AnyCancellable {
        ensureMainThread()
            .sink { [weak target] input in
                guard let strongTarget = target else { return }
                receiveValue(strongTarget, input)
            }
    }
}

extension Publisher where Failure == Never {
    func mapOnMainWith<T: AnyObject, V>(_ requires: T, transform: @escaping @MainActor (T, Output) -> V?) -> AnyPublisher<V, Never> {
        ensureMainThread()
            .compactMap { [weak requires] input in
                guard let requires else { return nil }
                return transform(requires, input)
            }
            .eraseToAnyPublisher()
    }
}
