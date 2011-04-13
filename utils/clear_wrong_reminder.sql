select * from 'mauve_alerts' where update_type='cleared' and will_unacknowledge_at != 0;

update 'mauve_alerts' set will_unacknowledge_at=NULL where update_type='cleared' and will_unacknowledge_at != 0;

