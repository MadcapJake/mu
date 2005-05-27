use v6;

# perl 5's Class::Publisher redone for all the Perl 6 OOP goodness

# something which does publisher can send events
# something which does subscriber can recieve them
# two kinds of things that can do subscriber:
# - Code
# - Object

# The notification process involves:
# creating an *event*
# getting the *subscriptions* for it, and converting them to *notifications* when they match
# asking the notifications to dispatch themselves

# the code tries to provide reusable code for driving events, and implements a
# "named event" mechanism, for Class::Publisher like behavior.

module Class::Events-0.0.1;

role Class::Events::Publisher {
	use Set;
	has Set $.subscriptions; # FIXME both instance data and class data

	method notify (Class::Events::Event $event) {
		(.get_notifications($event) ==> .mk_notifications)».dispatch;
	}
	
	method notify (*@args) {
		.notify(Class::Events::Event(*@args));
	}

	method mk_notifications (*@subscriptions of Class::Events::Subscription) {
		map { Class::Events::Notification.new(:subscriber($_), :event($event)) } *@subscriptions;
	}
	
	method get_subscriptions (Class::Events::Publisher $publisher, Class::Publisher::Event $event) {
		grep { .match($event) } gather {
			take $.subscriptions.members;

			# FIXME this is bullshit - i ought to read the details
			#for $class ($self.meta.superclasses){
			#	take $class.subscriptions;
			#}
		}
	}

	method add_subscription ($subscription) {
		$.subscriptions.insert($subscription);
	}

	method remove_subscription ($subscription) {
		$.subscriptions.remove($subscription);
	}
}

role Class::Events::Subscriber {
	# used only to control mmd
}

class Class::Events::Subscription {
	has Class::Events::Publisher $.publisher;
	has Class::Events::Subscriber $.subscriber;

	method match ($notification) {
		# this is really up to your subscription and event subclasses to define these
	}

	method delete {
		$.publisher.remove_subscription($?SELF);
	}
}

class Class::Events::Subscription::Named {
	is Class::Events::Subscription;

	has $.name;

	role Class::Events::Publisher {
		use Set;
		has %.subscriptions of Set;

		# when you say add_subscription("foo", ...) then "foo" is the name of the subscription
		method add_subscription (String $name, $subscriber = $?CALLER::?SELF) {
			( %.subscriptions<$name> ||= Set.new ).insert( Class::Events::Subscription::Named.new(:name($name), :subscriber($subscriber), :publisher($?SELF)) );
		}

		method remove_subscription (Class::Events::Subscription::Named $subscription) {
			%.subscriptions<$subscrption.name>.remove($subscription);
		}
		
		method get_subscriptions (Class::Publisher::Event::Named $event) {
			# an optimizing lookup for named events stores things in a hash to reduce algorithmic complexity
			gather {
				given $event.name {
					when '*' { take %.subscription.values».members };
					default { take %.subscriptions<$_>.members }
					# FIXME look at superclass subscriptions too
				}
			}
		}
	
		method notify (String $name, *@args) {
			$publisher.notify(Class::Events::Event::Named.new($name));
		}
	}
}

class Class::Events::Event {
	# pretty much an abstract baseclass
}

class Class::Events::Event::Named {
	has $.name;

	method new ($.name) {
		super;
	}

}

class Class::Events::Notification {
	has Class::Events::Subscription $.subscription;
	has Class::Events::Event $.event;

	multi method dispatch (::?CLASS $notification) {
		dispatch($notification, $.subscription.subscriber);
	}
	
	multi method dispatch (::?CLASS $notification, Code & Class::Events::Subscriber $subscriber) {
		$subscriber.($.subscription, $.event.args);
	}

	multi method dispatch (::?CLASS $notification, Class::Events::Subscriber $subscriber) {
		$subscriber.update($.subscription, $.event.args);
	}
}

