'use strict';
'require view';
'require form';

// Project code format is tabs, not spaces
return view.extend({
	render: function() {
		let m, s, o;
		m = new form.Map('general', _('Night Mode'),
			_('Night mode for leds.'));

		s = m.section(form.TypedSection, 'first', _('LED indication'));
		s.anonymous = true;

		o = s.option(form.Flag, 'button1', _('Led off:'));
		o.default = '1';
		o.rmempty = false;

		s = m.section(form.TypedSection, 'second', _('Night Mode'));
		s.anonymous = true;

		o = s.option(form.Flag, 'button2', _('Scheduled:'));
		o.default = '1';
		o.rmempty = false;

		let t1 =s.option(form.Value, 'first_time', _('Time starts leds:'),
			_('Time example: HH:MM'));
			t1.depends('button2', '1');
			t1.validate = function(section_id, value) {
				if (!value) return true;
				var timeRegex = /^(([0-1]?[0-9]|2[0-3]):[0-5][0-9]|(0?[1-9]|1[0-2]):[0-5][0-9]\s*([AaPp][Mm]))$/;
				if (timeRegex.test(value)) {
					return true;
				}
				return _('Invalid time format. Use HH:MM');
			};
			t1.rmempty = false;
			t1.default = '06:00';
			t1.placeholder = '06:00';

		let t2 =s.option(form.Value, 'second_time', _('Time stop leds:'),
			_('Time example: HH:MM'));
			t2.depends('button2', '1');
			t2.validate = function(section_id, value) {
				if (!value) return true;
				var timeRegex = /^(([0-1]?[0-9]|2[0-3]):[0-5][0-9]|(0?[1-9]|1[0-2]):[0-5][0-9]\s*([AaPp][Mm]))$/;
				if (timeRegex.test(value)) {
					return true;
				}
				return _('Invalid time format. Use HH:MM');
			};
			t2.rmempty = false;
			t2.default = '22:00';
			t2.placeholder = '22:00';

		return m.render();
	},
});
