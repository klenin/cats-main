function show_datepicker(el, name) {
  var input = $(el).parent().children('[name=' + name + ']');
  var date_time = input.val().split(/\s+/);
  var time = date_time[1] ? ' ' + date_time[1] : '';
  input.datepicker({
    trigger: el,
    autoShow: true,
    autoHide: true,
    format: 'dd.mm.yyyy',
    weekStart: 1,
    date: date_time[0],
    pick: function(event, date) {
      input.val(input.datepicker('getDate', true) + time);
      input.datepicker('destroy');
      event.preventDefault();
    },
  });
}

function init_datepickers(lang) {
  $.fn.datepicker.languages['en'] = {
  };
  $.fn.datepicker.languages['ru'] = {
    days: ['Воскресенье', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'],
    daysShort: ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'],
    daysMin: ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'],
    months: ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'],
    monthsShort: ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек']
  };
  $.fn.datepicker.languages['cn'] = {
    format: 'yyyy年mm月dd日',
    days: ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'],
    daysShort: ['周日', '周一', '周二', '周三', '周四', '周五', '周六'],
    daysMin: ['日', '一', '二', '三', '四', '五', '六'],
    months: ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'],
    monthsShort: ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'],
    yearFirst: true,
    yearSuffix: '年'
  };
  $.fn.datepicker.setDefaults({language: lang});
}
