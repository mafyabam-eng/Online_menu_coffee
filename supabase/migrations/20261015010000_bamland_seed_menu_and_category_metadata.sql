alter table public.menu_categories
  add column if not exists name_fa text not null default '',
  add column if not exists icon text not null default '✦',
  add column if not exists subtitle text not null default '';

insert into public.menu_categories(name, name_fa, icon, subtitle, sort_order, is_active)
values
 ('Mocktail','ماکتل و نوشیدنی‌های ترکیبی','◉','ترکیب‌های خنک و رنگارنگ',1,true),
 ('Tea Bar','چای و دمنوش','♨','آرامش در هر فنجان',2,true),
 ('Ice Bar','نوشیدنی‌های سرد','❄','خنک، تازه و پرانرژی',3,true),
 ('Hot Coffee Bar','قهوه‌های گرم','☕','عطر قهوه، شروعی دلنشین',4,true),
 ('Shake','شیک و نوشیدنی‌های غلیظ','✧','یک دلخوشی خنک و خامه‌ای',5,true),
 ('Persian Bar','نوشیدنی‌های ایرانی','❋','طعم‌های آشنا، حال‌وهوای اصیل',6,true),
 ('Cakes & Desserts','کیک و دسر','♧','پایان شیرین یک قرار خوب',7,true)
on conflict do nothing;

insert into public.menu_items(category_id,name,description,price,serving_minutes,sort_order,is_active)
select c.id,v.name,v.description,v.price,v.minutes,v.sort_order,true
from (values
 ('Mocktail','موهیتو کلاسیک','نعناع تازه، لیموترش و خنکی دلچسب',145000::numeric,7,1),
 ('Mocktail','رد سان‌رایز','ترکیب میوه‌ای با طعمی ترش و شیرین',155000::numeric,8,2),
 ('Mocktail','بلو لاگون','نوشیدنی خنک با حال‌وهوای استوایی',150000::numeric,7,3),
 ('Tea Bar','چای ایرانی','چای خوش‌عطر، مناسب یک مکث کوتاه',85000::numeric,5,1),
 ('Tea Bar','دمنوش آرامش','ترکیبی گیاهی با عطری ملایم',115000::numeric,8,2),
 ('Tea Bar','چای ماسالا','چای ادویه‌ای با بافتی گرم و معطر',135000::numeric,8,3),
 ('Ice Bar','آیس لاته','اسپرسو و شیر خنک روی یخ',145000::numeric,6,1),
 ('Ice Bar','آیس آمریکانو','اسپرسو با آب خنک و یخ',120000::numeric,5,2),
 ('Ice Bar','آیس‌تی لیمو','چای سرد با طعم روشن لیمو',110000::numeric,6,3),
 ('Hot Coffee Bar','اسپرسو','شات قهوه با کرمای غلیظ و عطر ماندگار',95000::numeric,4,1),
 ('Hot Coffee Bar','کاپوچینو','اسپرسو، شیر بخارداده و فوم لطیف',145000::numeric,7,2),
 ('Hot Coffee Bar','لاته','اسپرسو با شیر مخملی و بافت متعادل',150000::numeric,7,3),
 ('Shake','شیک شکلات','شیر و شکلات با بافتی غلیظ',175000::numeric,9,1),
 ('Shake','شیک وانیل','طعم لطیف وانیل با بافت خامه‌ای',165000::numeric,8,2),
 ('Shake','شیک توت‌فرنگی','ترکیب میوه‌ای با طعمی شیرین',175000::numeric,9,3),
 ('Persian Bar','سکنجبین و خیار','نوشیدنی سنتی با خیار و نعناع',120000::numeric,7,1),
 ('Persian Bar','شربت زعفران','عطر زعفران در یک نوشیدنی لطیف',135000::numeric,7,2),
 ('Persian Bar','بیدمشک','نوشیدنی خوش‌عطر با حال‌وهوای سنتی',120000::numeric,6,3),
 ('Cakes & Desserts','چیزکیک روز','دسر لطیف با بافتی خامه‌ای',185000::numeric,10,1),
 ('Cakes & Desserts','براونی شکلاتی','کیک شکلاتی با بافتی غنی',155000::numeric,8,2),
 ('Cakes & Desserts','کیک روز','انتخاب روز از ویترین کافه',145000::numeric,8,3)
) as v(category_name,name,description,price,minutes,sort_order)
join public.menu_categories c on c.name=v.category_name
where not exists (
 select 1 from public.menu_items mi where mi.category_id=c.id and mi.name=v.name
);

create index if not exists menu_items_category_id_idx on public.menu_items(category_id);
create index if not exists order_items_order_id_idx on public.order_items(order_id);
create index if not exists order_items_menu_item_id_idx on public.order_items(menu_item_id);
create index if not exists reviews_order_id_idx on public.reviews(order_id);
